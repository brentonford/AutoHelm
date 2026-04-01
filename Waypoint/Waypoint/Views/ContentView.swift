import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth: BluetoothManager
    @StateObject private var spotLockController:    SpotLockController
    @StateObject private var waypointNavController: WaypointNavController
    @StateObject private var trackRecorder:         TrackRecorder

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0

    init() {
        let bluetooth = BluetoothManager()
        _bluetooth             = StateObject(wrappedValue: bluetooth)
        _spotLockController    = StateObject(wrappedValue: SpotLockController(bluetooth: bluetooth))
        _waypointNavController = StateObject(wrappedValue: WaypointNavController(bluetooth: bluetooth))
        _trackRecorder         = StateObject(wrappedValue: TrackRecorder(bluetooth: bluetooth))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView()
            }
            .tabItem { Label("Map", systemImage: "map") }
            .accessibilityLabel("Map Tab")
            .tag(0)

            NavigationStack {
                HelmControlView()
            }
            .tabItem { Label("Helm", systemImage: "helm") }
            .accessibilityLabel("Helm Control Tab")
            .tag(1)

            NavigationStack {
                WaypointListView()
            }
            .tabItem { Label("Waypoints", systemImage: "mappin.and.ellipse") }
            .accessibilityLabel("Waypoints Tab")
            .tag(2)

            NavigationStack {
                TrackListView()
            }
            .tabItem { Label("Tracks", systemImage: "chart.xyaxis.line") }
            .accessibilityLabel("Tracks Tab")
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .accessibilityLabel("Settings Tab")
            .tag(4)
        }
        .environmentObject(bluetooth)
        .environmentObject(spotLockController)
        .environmentObject(waypointNavController)
        .environmentObject(trackRecorder)
        .task {
            bluetooth.initialize()
            trackRecorder.setContext(modelContext)
        }
    }
}
