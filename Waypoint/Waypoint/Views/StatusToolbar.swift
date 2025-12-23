import SwiftUI

struct StatusToolbar: ToolbarContent {
    @EnvironmentObject private var bluetooth: BluetoothManager
    let showWaypointList: () -> Void
    
    private var compassColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard bluetooth.deviceStatus != nil else { return .red }
        return .green
    }
    
    private var navigationColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard let status = bluetooth.deviceStatus else { return .red }
        return status.isNavigationReady ? .green : .orange
    }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 16) {
                SignalStrengthIndicator(
                    label: "BLE:",
                    signalStrength: bluetooth.signalStrength
                )
                
                if bluetooth.connectionState == .connected, let status = bluetooth.deviceStatus {
                    GPSQualityIndicator(
                        label: "GPS:",
                        quality: status.gpsQuality
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