import SwiftUI

struct SignalStrengthIndicator: View {
    let label: String
    let signalStrength: BLESignalStrength

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            
            if signalStrength == .disconnected {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(Color.red)
            } else {
                HStack(spacing: 2) {
                    ForEach(1...4, id: \.self) { bar in
                        Rectangle()
                            .fill(bar <= signalStrength.bars ? Color(signalStrength.color) : Color.gray.opacity(0.3))
                            .frame(width: 3, height: CGFloat(bar) * 3)
                    }
                }
            }
        }
    }
}

struct GPSQualityIndicator: View {
    let label: String
    let quality: GPSQuality

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Image(systemName: quality.icon)
                .font(.caption)
                .foregroundColor(Color(quality.color))
        }
    }
}

struct StatusIndicator: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

struct StatusToolbar: ToolbarContent {
    @ObservedObject var bluetooth: BluetoothManager
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
        
        // ToolbarItem(placement: .topBarTrailing) {
        //     Button {
        //         showWaypointList()
        //     } label: {
        //         Label("Waypoints", systemImage: "list.bullet")
        //     }
        // }
    }
}