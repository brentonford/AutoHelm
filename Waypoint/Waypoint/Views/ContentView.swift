import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    
    @State private var waypoints: [Waypoint] = []
    @State private var selectedWaypoint: Waypoint?
    @State private var selectedTab = 0
    @State private var navigationEnabled = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(
                    selectedWaypoint: $selectedWaypoint,
                    waypoints: $waypoints,
                    navigationEnabled: $navigationEnabled
                )
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(0)
            
            NavigationStack {
                HelmControlView(selectedWaypoint: selectedWaypoint, navigationEnabled: $navigationEnabled)
            }
            .tabItem {
                Label("Helm", systemImage: "helm")
            }
            .tag(1)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .environmentObject(bluetooth)
        .environmentObject(locationManager)
        .task {
            locationManager.requestAuthorization()
            bluetooth.initialize()
        }
    }
}

#Preview {
    ContentView()
}
