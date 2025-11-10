import SwiftUI
import MapKit

struct HelmControlView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @StateObject private var locationManager = LocationManager()
    @State private var showingWaypointAlert = false
    @State private var testWaypointName = ""
    @State private var selectedTestWaypoint: TestWaypoint?
    @State private var navigationEnabled = false
    @State private var previousNavigationState = false
    
    private let testWaypoints = [
        TestWaypoint(name: "Sydney Opera House", coordinate: CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153)),
        TestWaypoint(name: "Sydney Harbour Bridge", coordinate: CLLocationCoordinate2D(latitude: -33.8523, longitude: 151.2108)),
        TestWaypoint(name: "Bondi Beach", coordinate: CLLocationCoordinate2D(latitude: -33.8915, longitude: 151.2767)),
        TestWaypoint(name: "Manly Beach", coordinate: CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.2840))
    ]
    
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
                    
                    // Waypoint Control
                    waypointControlSection
                    
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
            .alert("Send Test Waypoint", isPresented: $showingWaypointAlert) {
                Button("Send") {
                    if let waypoint = selectedTestWaypoint {
                        sendTestWaypoint(waypoint)
                    }
                }
                Button("Cancel") {
                    selectedTestWaypoint = nil
                }
            } message: {
                if let waypoint = selectedTestWaypoint {
                    Text("Send \(waypoint.name) (\(String(format: "%.6f", waypoint.coordinate.latitude)), \(String(format: "%.6f", waypoint.coordinate.longitude))) to Helm device?")
                }
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
                        statusRow("Target", value: "\(String(format: "%.6f", target.latitude)), \(String(format: "%.6f", target.longitude))")
                        statusRow("Distance", value: "\(String(format: "%.1f", status.distance))m")
                        statusRow("Bearing", value: "\(String(format: "%.1f", status.bearing))°")
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
    
    private var waypointControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Waypoint Testing")
                .font(.headline)
            
            if bluetoothManager.isConnected {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(testWaypoints, id: \.name) { waypoint in
                        Button(action: {
                            selectedTestWaypoint = waypoint
                            showingWaypointAlert = true
                        }) {
                            VStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
                                Text(waypoint.name)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBlue).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            } else {
                Text("Connect to Helm device to send waypoints")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
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
    
    private func sendTestWaypoint(_ waypoint: TestWaypoint) {
        let coordinate = waypoint.coordinate
        
        bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        print("Sent waypoint: \(waypoint.name) (\(coordinate.latitude), \(coordinate.longitude))")
    }
}

struct TestWaypoint {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    HelmControlView()
        .environmentObject(BluetoothManager())
}