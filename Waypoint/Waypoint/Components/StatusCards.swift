import SwiftUI

// MARK: - Navigation Status Card
struct NavigationStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Navigation")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                
                StatusIndicator(
                    isActive: status.navigationActive,
                    activeText: "Active",
                    inactiveText: "Standby",
                    activeColor: .green,
                    inactiveColor: .orange
                )
            }
            
            HStack {
                NavigationMetricsView(status: status)
                Spacer()
                EnhancedCompassView(heading: status.heading, bearing: status.bearing)
                    .frame(width: 80, height: 80)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - GPS Status Card
struct GPSStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPS Status")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                StatusIndicator(
                    isActive: status.hasGpsFix,
                    activeText: "Fix",
                    inactiveText: "No Fix",
                    activeColor: .green,
                    inactiveColor: .red
                )
            }
            
            GPSMetricsView(status: status)
        }
        .padding(12)
        .background(status.hasGpsFix ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Target Status Card
struct TargetStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Waypoint")
                .font(.callout)
                .fontWeight(.medium)
            
            TargetCoordinatesView(status: status)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Views
struct StatusIndicator: View {
    let isActive: Bool
    let activeText: String
    let inactiveText: String
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? activeColor : inactiveColor)
                .frame(width: 8, height: 8)
            Text(isActive ? activeText : inactiveText)
                .font(.caption)
                .foregroundColor(isActive ? activeColor : inactiveColor)
        }
    }
}

struct NavigationMetricsView: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetricRow(icon: "location.north.fill", color: .blue, 
                     text: "Heading: \(String(format: "%.1f", status.heading))°")
            MetricRow(icon: "arrow.triangle.turn.up.right.diamond.fill", color: .green,
                     text: "Bearing: \(String(format: "%.1f", status.bearing))°")
            MetricRow(icon: "ruler.fill", color: .orange,
                     text: "Distance: \(status.distanceText)")
        }
    }
}

struct GPSMetricsView: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricRow(icon: "dot.radiowaves.up", color: .blue,
                     text: "Satellites: \(status.satellites)")
            MetricRow(icon: "location.fill", color: .blue,
                     text: "Lat: \(String(format: "%.6f", status.currentLat))")
            MetricRow(icon: "location.fill", color: .blue,
                     text: "Lon: \(String(format: "%.6f", status.currentLon))")
            MetricRow(icon: "mountain.2.fill", color: .brown,
                     text: "Alt: \(String(format: "%.1f", status.altitude)) m")
        }
    }
}

struct TargetCoordinatesView: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricRow(icon: "mappin.circle.fill", color: .red,
                     text: "Lat: \(String(format: "%.6f", status.targetLat))")
            MetricRow(icon: "mappin.circle.fill", color: .red,
                     text: "Lon: \(String(format: "%.6f", status.targetLon))")
        }
    }
}

struct MetricRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
        }
    }
}