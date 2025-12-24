import SwiftUI

struct StatusToolbar: ToolbarContent {
    @EnvironmentObject private var bluetooth: BluetoothManager
    let showWaypointList: () -> Void
    
    private var compassColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard bluetooth.sensorData != nil else { return .red }
        return .green
    }
    
    private var navigationColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard let sensors = bluetooth.sensorData else { return .red }
        return sensors.isNavigationReady ? .green : .orange
    }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 16) {
                SignalStrengthIndicator(
                    label: "BLE:",
                    signalStrength: bluetooth.signalStrength
                )
                
                if bluetooth.connectionState == .connected, let sensors = bluetooth.sensorData {
                    GPSQualityIndicator(
                        label: "GPS:",
                        quality: sensors.gpsQuality
                    )
                } else {
                    GPSQualityIndicator(
                        label: "GPS:",
                        quality: .noFix
                    )
                }
                
                StatusIndicator(label: "Compass:", color: compassColor)
                StatusIndicator(label: "Navigation:", color: navigationColor)
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showWaypointList()
            } label: {
                Label("Waypoints", systemImage: "list.bullet")
            }
        }
    }
}