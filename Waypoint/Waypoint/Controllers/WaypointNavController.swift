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
    @Published private(set) var targetWaypoint:  Waypoint?
    @Published private(set) var distanceMetres:  Double   = 0
    @Published private(set) var targetBearing:   Double   = 0
    @Published private(set) var currentSpeed:    Int      = 0
    @Published private(set) var isArriving:      Bool     = false

    // MARK: - Private

    private let bluetooth: BluetoothManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        observeTelemetry()
    }

    // MARK: - Observe device telemetry

    private func observeTelemetry() {
        bluetooth.$sensorData
            .sink { [weak self] data in
                guard let self else { return }
                let active = data?.isNavActive ?? false
                self.isActive = active
                if active, let data {
                    self.distanceMetres = data.navDistanceMetres
                    self.targetBearing  = data.navTargetBearing
                    self.currentSpeed   = data.navCurrentSpeed
                    self.isArriving     = data.isNavArriving
                } else if !active {
                    self.distanceMetres = 0
                    self.currentSpeed   = 0
                    self.isArriving     = false
                    // targetWaypoint cleared by arrival or explicit cancel
                    if self.targetWaypoint != nil {
                        self.targetWaypoint = nil
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Uploads navigation settings, waits for the write to arrive, then starts navigation.
    /// The 150 ms gap ensures the device has applied the latest settings before the
    /// NAV_START command is processed.
    func navigate(to waypoint: Waypoint, speedLevel: Int) {
        targetWaypoint = waypoint
        Task {
            bluetooth.sendNavSettings(DataStore.shared.navSettings)
            try? await Task.sleep(for: .milliseconds(150))
            bluetooth.startNavigation(to: waypoint.coordinate, speedLevel: speedLevel)
        }
    }

    /// Cancels active navigation and ramps the motor down.
    func cancel() {
        bluetooth.cancelNavigation()
        targetWaypoint = nil
    }
}
