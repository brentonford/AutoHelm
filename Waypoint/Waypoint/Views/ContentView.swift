import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    
    @State private var waypoints: [Waypoint] = []
    @State private var selectedWaypoint: Waypoint?
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(
                    selectedWaypoint: $selectedWaypoint,
                    waypoints: $waypoints
                )
                .navigationTitle("Waypoint")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        ConnectionIndicator(state: bluetooth.connectionState)
                    }
                }
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(0)
            
            NavigationStack {
                HelmControlView(selectedWaypoint: selectedWaypoint)
            }
            .tabItem {
                Label("Helm", systemImage: "helm")
            }
            .tag(1)
        }
        .environmentObject(bluetooth)
        .environmentObject(locationManager)
        .task {
            locationManager.requestAuthorization()
            bluetooth.initialize()
        }
    }
}

// MARK: - Connection Indicator

struct ConnectionIndicator: View {
    let state: ConnectionState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            
            Text(state == .connected ? "Helm" : "")
                .font(.caption)
        }
    }
    
    private var indicatorColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .scanning: return .orange
        case .disconnected: return .red
        }
    }
}

#Preview {
    ContentView()
}