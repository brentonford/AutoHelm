import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @StateObject private var navigationManager: NavigationManager
    
    @Binding var waypoints: [Waypoint]
    @Binding var selectedWaypoint: Waypoint?
    @Binding var navigationEnabled: Bool
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingArrivalAlert = false
    @State private var showingWaypointList = false
    
    init(waypoints: Binding<[Waypoint]>, selectedWaypoint: Binding<Waypoint?>, navigationEnabled: Binding<Bool>) {
        self._waypoints = waypoints
        self._selectedWaypoint = selectedWaypoint
        self._navigationEnabled = navigationEnabled
        
        let bluetooth = BluetoothManager()
        self._navigationManager = StateObject(wrappedValue: NavigationManager(bluetoothManager: bluetooth))
    }
    
    private var canNavigate: Bool {
        bluetooth.connectionState == .connected &&
        bluetooth.sensorData?.isNavigationReady == true
    }

    var body: some View {
        List {
            motorControlSection
            spotLockSection
            autonomousNavigationSection
            autonomousCommandSection
            connectionSection
            gpsStatusSection
            compassSection
        }
        .toolbar {
            StatusToolbar(bluetooth: bluetooth) {
                showingWaypointList = true
            }
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(
                waypoints: $waypoints,
                selectedWaypoint: $selectedWaypoint,
                navigationEnabled: $navigationEnabled
            )
        }
        .alert("Arrived!", isPresented: $showingArrivalAlert) {
            Button("OK") {}
        } message: {
            if let waypoint = selectedWaypoint {
                Text("You have arrived at \(waypoint.name)")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: navigationManager.state) { _, newState in
            if case .idle = newState {
                navigationEnabled = false
            }
        }
    }
    
    private var motorControlSection: some View {
        Section {
            ManualMotorControls(bluetooth: bluetooth) {
                Task {
                    await navigationManager.stopNavigation()
                }
            }
        } header: {
            Text("Manual Remote Control")
        } footer: {
            Text("Manual control automatically disables autonomous navigation")
        }
    }
    
    private var spotLockSection: some View {
        Section {
            SpotLockControls(
                navigationManager: navigationManager,
                canNavigate: canNavigate
            )
        } header: {
            Text("Spot Lock")
        } footer: {
            Text("Maintains position within 2m radius with steering corrections")
        }
    }
    
    private var autonomousNavigationSection: some View {
        Section {
            if let waypoint = selectedWaypoint {
                WaypointInfo(waypoint: waypoint)
                
                NavigationControls(
                    waypoint: waypoint,
                    navigationManager: navigationManager,
                    bluetooth: bluetooth,
                    navigationEnabled: $navigationEnabled,
                    canNavigate: canNavigate,
                    showingArrivalAlert: $showingArrivalAlert
                )
                
                if let sensors = bluetooth.sensorData {
                    NavigationMetrics(
                        waypoint: waypoint,
                        sensors: sensors,
                        targetSpeed: navigationManager.speedController.targetSpeedKmh
                    )
                }
            } else {
                Text("No waypoint selected")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Autonomous Navigation")
        } footer: {
            Text("App handles all navigation logic and timing")
        }
    }
    
    private var autonomousCommandSection: some View {
        Section {
            if navigationEnabled {
                NavigationPhaseView(phase: navigationManager.currentPhase)
                
                LabeledContent("Target Speed") {
                    Text(String(format: "%.1f km/hr", navigationManager.speedController.targetSpeedKmh))
                        .foregroundColor(.blue)
                }
                
                CommandStatusView(
                    steeringCommand: navigationManager.steeringCommand,
                    speedCommand: navigationManager.speedCommand
                )
                
                LabeledContent("Power Level") {
                    Text("\(navigationManager.motorController.currentSpeedLevel)/10")
                }
                
                if let sensors = bluetooth.sensorData {
                    SpeedStatusView(
                        gpsSpeed: sensors.speedKmh,
                        powerLevel: navigationManager.motorController.currentSpeedLevel
                    )
                }
            } else {
                Text("Navigation disabled")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Autonomous Commands")
        } footer: {
            Text("2s intervals, gradual speed changes, ±15° steering tolerance")
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

struct NavigationControls: View {
    let waypoint: Waypoint
    let navigationManager: NavigationManager
    let bluetooth: BluetoothManager
    @Binding var navigationEnabled: Bool
    let canNavigate: Bool
    @Binding var showingArrivalAlert: Bool
    
    var body: some View {
        HStack {
            Text(navigationEnabled ? "Navigating" : "Idle")
                .foregroundColor(.secondary)
            
            Spacer()
            
            if navigationEnabled {
                Button {
                    Task {
                        await navigationManager.stopNavigation()
                    }
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Navigation")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.red)
            } else {
                Button {
                    Task {
                        do {
                            guard let sensors = bluetooth.sensorData else { return }
                            try await navigationManager.startNavigation(
                                to: waypoint,
                                from: sensors.currentLocation
                            )
                            navigationEnabled = true
                        } catch {
                            showingArrivalAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Navigate to Waypoint")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canNavigate)
            }
        }
    }
}

#Preview {
    HelmControlView(
        waypoints: .constant([]),
        selectedWaypoint: .constant(nil),
        navigationEnabled: .constant(false)
    )
    .environmentObject(BluetoothManager())
}