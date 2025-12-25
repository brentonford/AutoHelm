import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @ObservedObject private var dataStore = DataStore.shared
    
    @State private var selectedWaypoint: Waypoint?
    @State private var selectedTab = 0
    @State private var navigationEnabled = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(
                    selectedWaypoint: $selectedWaypoint,
                    waypoints: $dataStore.waypoints,
                    navigationEnabled: $navigationEnabled,
                    bluetooth: bluetooth
                )
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .accessibilityLabel("Map Tab")
            .tag(0)
            
            NavigationStack {
                HelmControlView(
                    waypoints: $dataStore.waypoints,
                    selectedWaypoint: $selectedWaypoint,
                    navigationEnabled: $navigationEnabled
                )
            }
            .tabItem {
                Label("Helm", systemImage: "helm")
            }
            .accessibilityLabel("Helm Control Tab")
            .tag(1)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Settings Tab")
            .tag(2)
        }
        .environmentObject(bluetooth)
        .task {
            bluetooth.initialize()
        }
        .onChange(of: dataStore.waypoints) { _, _ in
            dataStore.saveWaypoints()
        }
    }
}

#Preview {
    ContentView()
}