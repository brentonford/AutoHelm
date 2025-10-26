import SwiftUI

@main
struct WaypointApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var offlineTileManager = OfflineTileManager()
    @StateObject private var waypointManager = WaypointManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WaypointMapView(
                locationManager: locationManager,
                bluetoothManager: bluetoothManager,
                waypointManager: waypointManager,
                offlineTileManager: offlineTileManager
            )
            .tabItem {
                Label("Waypoint", systemImage: "map.fill")
            }
            .tag(0)
            
            CombinedStatusView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Helm", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(1)
            
            CombinedSettingsView(
                bluetoothManager: bluetoothManager, 
                locationManager: locationManager, 
                offlineTileManager: offlineTileManager
            )
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .onAppear {
            locationManager.requestAuthorization()
        }
    }
}