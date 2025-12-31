import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var spotLockController: SpotLockController
    
    @Binding var waypoints: [Waypoint]
    @Binding var selectedWaypoint: Waypoint?
    
    @State private var showingWaypointList = false
    
    private var canNavigate: Bool {
        bluetooth.connectionState == .connected &&
        bluetooth.sensorData?.isNavigationReady == true
    }

    var body: some View {
        List {
            motorControlSection
            spotLockSection
            connectionSection
            gpsStatusSection
            compassSection
        }
        .navigationTitle("Helm Control")
        .toolbar {
            StatusToolbar(bluetooth: bluetooth) {
                showingWaypointList = true
            }
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(
                waypoints: $waypoints,
                selectedWaypoint: $selectedWaypoint
            )
        }
    }
    
    private var motorControlSection: some View {
        Section {
            ManualMotorControls(bluetooth: bluetooth) {
                Task {
                    await spotLockController.disengage()
                }
            }
        } header: {
            Text("Manual Remote Control")
        } footer: {
            Text("Manual control automatically disables Spot Lock")
        }
    }
    
    private var spotLockSection: some View {
        Section {
            SpotLockControls(
                spotLockController: spotLockController,
                canNavigate: canNavigate,
                onEngageHere: {
                    Task {
                        guard let sensors = bluetooth.sensorData else { return }
                        await spotLockController.engage(at: sensors.currentLocation)
                    }
                },
                onEngageAtWaypoint: {
                    Task {
                        guard let waypoint = selectedWaypoint else { return }
                        await spotLockController.engage(at: waypoint.coordinate)
                    }
                },
                onDisengage: {
                    Task {
                        await spotLockController.disengage()
                    }
                },
                onJog: { direction in
                    spotLockController.jog(direction: direction)
                }
            )
        } header: {
            Text("Spot Lock")
        } footer: {
            Text("Maintains position within 2m radius with automatic corrections")
        }
    }
    
    private var connectionSection: some View {
        Section("Helm Device") {
            ConnectionStatus(bluetooth: bluetooth)
        }
    }
    
    private var gpsStatusSection: some View {
        Section("GPS Status") {
            if let sensors = bluetooth.sensorData {
                GpsStatusView(sensors: sensors)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var compassSection: some View {
        Section("Compass") {
            if let sensors = bluetooth.sensorData {
                CompassStatusView(sensors: sensors)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    HelmControlView(
        waypoints: .constant([]),
        selectedWaypoint: .constant(nil)
    )
    .environmentObject(BluetoothManager())
    .environmentObject(SpotLockController(bluetooth: BluetoothManager()))
}