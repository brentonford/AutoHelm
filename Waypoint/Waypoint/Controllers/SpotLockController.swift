import Foundation
import CoreLocation
import Combine

/// Thin view-model proxy for the device-side SpotLock algorithm.
/// All navigation logic runs on the Helm ESP32; this class:
///   - Forwards engage/disengage/jog commands to the device via BluetoothManager
///   - Syncs published state from BLE sensor telemetry (sl_* JSON fields)
///   - Preserves the same public interface so all existing views compile unchanged
@MainActor
class SpotLockController: ObservableObject {

    // MARK: - Published Properties (UI Observable)

    @Published var lockPosition: CLLocationCoordinate2D?
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isEngaging: Bool = false
    @Published private(set) var isDisengaging: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    @Published private(set) var isApplyingThrust: Bool = false
    @Published private(set) var currentCorrectionBearing: Double = 0
    @Published private(set) var currentSpeedLevel: Int = 0
    @Published private(set) var isJogging: Bool = false
    @Published private(set) var cableRotation: Double = 0
    @Published private(set) var isCableTangled: Bool = false
    @Published private(set) var isFaulted: Bool = false

    // MARK: - Supporting Types (retained for view compatibility)

    enum JogDirection {
        case forward, back, left, right

        var commandName: String {
            switch self {
            case .forward: return "FORWARD"
            case .back:    return "BACK"
            case .left:    return "LEFT"
            case .right:   return "RIGHT"
            }
        }

        var compassHeading: Double {
            switch self {
            case .forward: return 0.0
            case .right:   return 90.0
            case .back:    return 180.0
            case .left:    return 270.0
            }
        }

        var compassName: String {
            switch self {
            case .forward: return "North"
            case .right:   return "East"
            case .back:    return "South"
            case .left:    return "West"
            }
        }
    }

    // MARK: - Private

    private let bluetooth: BluetoothManager
    private var cancellables = Set<AnyCancellable>()
    private var jogTimer: Timer?
    private var engageTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        observeSensorData()
        observeResponses()
    }

    // MARK: - Observe device telemetry

    private func observeSensorData() {
        bluetooth.$sensorData
            .sink { [weak self] data in
                guard let self else { return }
                let faulted = data?.currentHelmState == .fault
                self.isFaulted = faulted

                let active = faulted ? false : (data?.isSpotLockActive ?? false)

                if self.isDisengaging && !active {
                    self.isDisengaging = false
                }

                if active {
                    self.isEngaging = false
                    self.engageTimeoutTask?.cancel()
                    self.engageTimeoutTask = nil
                }

                if faulted {
                    self.isDisengaging = false
                    self.isEngaging = false
                    self.engageTimeoutTask?.cancel()
                    self.engageTimeoutTask = nil
                }

                self.isActive = active
                if active, let data {
                    if let loc = data.spotLockLocation {
                        self.lockPosition = loc
                    }
                    self.distanceFromLock         = data.spotLockDistance
                    self.isApplyingThrust         = data.spotLockThrust
                    self.currentCorrectionBearing = data.spotLockBearing
                    self.currentSpeedLevel        = data.spotLockSpeed
                    self.cableRotation            = data.spotLockRotation
                    self.isCableTangled           = data.spotLockTangled
                } else if !active && !self.isEngaging {
                    self.distanceFromLock  = 0
                    self.isApplyingThrust  = false
                    self.currentSpeedLevel = 0
                }
            }
            .store(in: &cancellables)
    }

    private func observeResponses() {
        bluetooth.$lastResponse
            .compactMap { $0 }
            .sink { [weak self] response in
                guard let self else { return }
                guard self.isEngaging else { return }

                if response.ack == "SPOTLOCK_ENGAGED" {
                    self.isEngaging = false
                    self.engageTimeoutTask?.cancel()
                    self.engageTimeoutTask = nil
                } else if response.error != nil {
                    self.isEngaging = false
                    self.engageTimeoutTask?.cancel()
                    self.engageTimeoutTask = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Uploads current settings then engages SpotLock at the given position.
    func engage(at position: CLLocationCoordinate2D) async {
        bluetooth.sendSpotLockSettings(DataStore.shared.spotLockSettings)

        try? await Task.sleep(for: .milliseconds(150))

        lockPosition = position
        isEngaging = true
        isDisengaging = false
        bluetooth.engageSpotLock(at: position)

        engageTimeoutTask?.cancel()
        engageTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self.isEngaging, !self.isActive else { return }
            self.isEngaging = false
        }
    }

    /// Sends disengage command to the device.
    func disengage() async {
        guard isActive || isEngaging else { return }
        isEngaging = false
        engageTimeoutTask?.cancel()
        engageTimeoutTask = nil
        isDisengaging = true
        stopJog()
        bluetooth.disengageSpotLock()
    }

    /// Starts sending jog commands to the device (call on button press).
    func jogStart(direction: JogDirection) {
        guard isActive else { return }
        stopJog()
        isJogging = true
        sendJog(direction)
        jogTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isJogging else { return }
                self.sendJog(direction)
            }
        }
    }

    /// Stops sending jog commands (call on button release).
    func jogStop() {
        stopJog()
    }

    /// No-op: algorithm runs on device. Retained for ContentView timer compatibility.
    func update() async {}

    // MARK: - Private helpers

    private func sendJog(_ direction: JogDirection) {
        bluetooth.sendCommand("SPOTLOCK_JOG:\(direction.commandName)")
    }

    private func stopJog() {
        jogTimer?.invalidate()
        jogTimer = nil
        isJogging = false
    }
}