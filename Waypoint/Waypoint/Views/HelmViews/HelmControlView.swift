import SwiftUI
import MapKit

struct HelmControlView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @StateObject private var locationManager = LocationManager()
    @State private var navigationEnabled = false
    @State private var previousNavigationState = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Connection Status
                    connectionStatusSection
                    
                    // Device Status
                    if bluetoothManager.isConnected {
                        deviceStatusSection
                    }
                    
                    // Waypoint Control removed
                    
                    // Navigation Control
                    if bluetoothManager.isConnected {
                        navigationControlSection
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Helm Control")
            .onAppear {
                locationManager.requestPermission()
            }
            .onChange(of: bluetoothManager.deviceStatus?.hasGpsFix) { oldValue, newValue in
                handleGpsFixChange(newValue)
            }

        }
    }
    
    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(bluetoothManager.isConnected ? .green : .red)
                    .frame(width: 16, height: 16)
                
                Text(bluetoothManager.isConnected ? "Helm Connected" : "Helm Disconnected")
                    .font(.body)
                
                Spacer()
                
                if bluetoothManager.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Status")
                .font(.headline)
            
            if let status = bluetoothManager.deviceStatus {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow("GPS Fix", value: status.hasGpsFix ? "Yes" : "No", color: status.hasGpsFix ? .green : .red)
                    statusRow("Satellites", value: "\(status.satellites)")
                    statusRow("Accuracy", value: status.gpsAccuracyDescription)
                    
                    if status.hasGpsFix {
                        statusRow("Position", value: "\(String(format: "%.6f", status.currentLat)), \(String(format: "%.6f", status.currentLon))")
                        statusRow("Altitude", value: "\(String(format: "%.1f", status.altitude))m")
                        statusRow("Heading", value: "\(String(format: "%.1f", status.heading))°")
                    }
                    
                    if let target = status.targetCoordinate {
                        Divider()
                        Text("Navigation Active")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                        
                        statusRow("Target", value: "\(String(format: "%.6f", target.latitude)), \(String(format: "%.6f", target.longitude))")
                        statusRow("Distance", value: "\(String(format: "%.1f", status.distance))m")
                        statusRow("Bearing", value: "\(String(format: "%.1f", status.bearing))°")
                        
                        // Visual navigation indicator
                        HStack {
                            Text("Direction:")
                                .foregroundColor(.secondary)
                            Spacer()
                            NavigationArrowView(bearing: status.bearing, currentHeading: status.heading)
                        }
                    }
                }
            } else {
                Text("Waiting for device status...")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    

    
    private var navigationControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Navigation Control")
                .font(.headline)
            
            VStack(spacing: 12) {
                Button(action: {
                    navigationEnabled.toggle()
                    if navigationEnabled {
                        print("Enable Navigation toggled ON")
                        bluetoothManager.enableNavigation()
                    } else {
                        print("Enable Navigation toggled OFF")
                        bluetoothManager.disableNavigation()
                    }
                }) {
                    HStack {
                        Image(systemName: navigationEnabled ? "stop.fill" : "play.fill")
                        Text(navigationEnabled ? "Disable Navigation" : "Enable Navigation")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!bluetoothManager.isConnected)
                
                Text("GPS Fix required for navigation")
                    .font(.caption)
                    .foregroundColor(bluetoothManager.deviceStatus?.hasGpsFix == true ? .secondary : .orange)
                
                if !bluetoothManager.isConnected {
                    Text("Connect to Helm device to control navigation")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private func handleGpsFixChange(_ hasGpsFix: Bool?) {
        guard let hasGpsFix = hasGpsFix else { return }
        
        if hasGpsFix {
            // GPS Fix restored - return to previous navigation state
            if previousNavigationState && !navigationEnabled {
                navigationEnabled = true
                bluetoothManager.enableNavigation()
                print("GPS Fix restored - Navigation re-enabled")
            }
        } else {
            // GPS Fix lost - temporarily disable navigation
            if navigationEnabled {
                previousNavigationState = true
                navigationEnabled = false
                bluetoothManager.disableNavigation()
                print("GPS Fix lost - Navigation temporarily disabled")
            }
        }
    }
    
    private func statusRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(.medium)
        }
    }
    
}

struct NavigationArrowView: View {
    let bearing: Double
    let currentHeading: Double
    
    private var relativeAngle: Double {
        let angle = bearing - currentHeading
        if angle > 180 {
            return angle - 360
        } else if angle < -180 {
            return angle + 360
        }
        return angle
    }
    
    var body: some View {
        Image(systemName: "arrow.up")
            .foregroundColor(.blue)
            .font(.title2)
            .rotationEffect(.degrees(relativeAngle))
            .animation(.easeInOut(duration: 0.3), value: relativeAngle)
    }
}

#Preview {
    HelmControlView()
        .environmentObject(BluetoothManager())
}