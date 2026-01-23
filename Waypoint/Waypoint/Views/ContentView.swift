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
        .onChange(of: spotLockController.isActive) { _, isActive in
            if isActive {
                startSpotLockTimer()
            } else {
                stopSpotLockTimer()
            }
        }
        .onChange(of: bluetooth.connectionState) { _, newState in
            if newState != .connected {
                Task {
                    await spotLockController.disengage()
                }
            }
        }
        .onDisappear {
            stopSpotLockTimer()
        }
    }
    
    @State private var spotLockTimer: Timer?
    
    private func startSpotLockTimer() {
        stopSpotLockTimer()
        spotLockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        Task { @MainActor in
            await spotLockController.update()
        }
    }
}
    
    private func stopSpotLockTimer() {
        spotLockTimer?.invalidate()
        spotLockTimer = nil
    }
}

#Preview {
    ContentView()
}