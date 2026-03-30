import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var spotLockController: SpotLockController

    @State private var selectedTab = 0

    init() {
        let bluetooth = BluetoothManager()
        _bluetooth = StateObject(wrappedValue: bluetooth)
        _spotLockController = StateObject(wrappedValue: SpotLockController(bluetooth: bluetooth))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .accessibilityLabel("Map Tab")
            .tag(0)

            NavigationStack {
                HelmControlView()
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
        .environmentObject(spotLockController)
        .task {
            bluetooth.initialize()
        }
    }
}
