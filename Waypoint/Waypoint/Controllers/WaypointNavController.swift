import Foundation
import CoreLocation
import Combine

/// Thin view-model proxy for the device-side waypoint navigation algorithm.
/// All navigation logic runs on the Helm ESP32; this class:
///   - Forwards start/cancel commands to the device via BluetoothManager
///   - Syncs published state from BLE nav_* telemetry fields
@MainActor
class WaypointNavController: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isActive:        Bool     = false
    @Published private(set) var isStarting:      Bool     = false
    @Published private(set) var targetWaypoint:  Waypoint?
    @Published private(set) var distanceMetres:  Double   = 0
    @Published private(set) var targetBearing:   Double   = 0
    @Published private(set) var currentSpeed:    Int      = 0
    @Published private(set) var isArriving:      Bool     = false
    @Published private(set) var isFaulted:       Bool     = false

    // MARK: - Private

    private let bluetooth: BluetoothManager
    private var cancellables = Set<AnyCancellable>()
    private var startTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        observeTelemetry()
        observeResponses()
    }

    // MARK: - Observe device telemetry

    private func observeTelemetry() {
        bluetooth.$sensorData
            .sink { [weak self] data in
                guard let self else { return }
                let faulted = data?.currentHelmState == .fault
                self.isFaulted = faulted

                let active = faulted ? false : (data?.isNavActive ?? false)

                if data?.currentHelmState == .navApproaching {
                    self.isStarting = false
                    self.startTimeoutTask?.cancel()
                    self.startTimeoutTask = nil
                }

                if faulted {
                    self.isStarting = false
                    self.startTimeoutTask?.cancel()
                    self.startTimeoutTask = nil
                }

                self.isActive = active
                if active, let data {
                    self.distanceMetres = data.navDistanceMetres
                    self.targetBearing  = data.navTargetBearing
                    self.currentSpeed   = data.navCurrentSpeed
                    self.isArriving     = data.isNavArriving
                } else if !active && !self.isStarting {
                    self.distanceMetres = 0
                    self.currentSpeed   = 0
                    self.isArriving     = false
                    self.targetWaypoint = nil
                }
            }
            .store(in: &cancellables)
    }

    private func observeResponses() {
        bluetooth.$lastResponse
            .compactMap { $0 }
            .sink { [weak self] response in
                guard let self else { return }
                guard self.isStarting else { return }

                if response.error != nil {
                    self.isStarting = false
                    self.targetWaypoint = nil
                    self.startTimeoutTask?.cancel()
                    self.startTimeoutTask = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func navigate(to waypoint: Waypoint, speedLevel: Int) {
        targetWaypoint = waypoint
        isStarting = true
        Task {
            bluetooth.sendNavSettings(DataStore.shared.navSettings)
            try? await Task.sleep(for: .milliseconds(150))
            bluetooth.startNavigation(to: waypoint.coordinate, speedLevel: speedLevel)

            startTimeoutTask?.cancel()
            startTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, self.isStarting else { return }
                self.isStarting = false
                if !self.isActive {
                    self.targetWaypoint = nil
                }
            }
        }
    }

    func cancel() {
        isStarting = false
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        bluetooth.cancelNavigation()
        targetWaypoint = nil
    }
}