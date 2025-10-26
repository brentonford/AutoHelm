import SwiftUI
import CoreBluetooth

// MARK: - Combined Status View
struct CombinedStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isConnectionSectionExpanded = false
    @State private var navigationEnabled = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Connection")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        
                        if bluetoothManager.isConnected {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text("(\(bluetoothManager.signalStrength) dBm)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isConnectionSectionExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isConnectionSectionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    if isConnectionSectionExpanded || !bluetoothManager.isConnected {
                        ConnectionSectionView(bluetoothManager: bluetoothManager)
                            .padding(.horizontal, 8)
                    }
                }
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                
                // Navigation Control Section
                if bluetoothManager.isConnected {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Navigation Control")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $navigationEnabled)
                                .onChange(of: navigationEnabled) { oldValue, newValue in
                                    bluetoothManager.setNavigationEnabled(newValue)
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        
                        HStack {
                            Image(systemName: navigationEnabled ? "location.fill" : "location.slash")
                                .foregroundColor(navigationEnabled ? .green : .red)
                            Text(navigationEnabled ? "Navigation Active" : "Navigation Disabled")
                                .font(.caption)
                                .foregroundColor(navigationEnabled ? .green : .red)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                }
                
                if bluetoothManager.isConnected {
                    if let status = bluetoothManager.arduinoStatus {
                        ScrollView {
                            VStack(spacing: 12) {
                                NavigationStatusCard(status: status)
                                GPSStatusCard(status: status)
                                if navigationEnabled {
                                    TargetStatusCard(status: status)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "clock")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("Waiting for Arduino data...")
                                .font(.callout)
                                .foregroundColor(.gray)
                            Text("Make sure the Arduino is powered on and GPS has a fix")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Arduino not connected")
                            .font(.callout)
                            .foregroundColor(.red)
                        Text("Use the connection controls above to establish connection")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    Spacer()
                }
            }
            .navigationTitle("Helm Status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Connection Section View
struct ConnectionSectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 12) {
            if bluetoothManager.isConnected {
                Button(action: {
                    bluetoothManager.disconnect()
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        Text("Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            } else {
                if !bluetoothManager.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Available Devices")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                            Button(action: {
                                bluetoothManager.connect(to: device)
                            }) {
                                HStack {
                                    Image(systemName: "sensor")
                                        .foregroundColor(.blue)
                                    Text(device.name ?? "Unknown Device")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                HStack(spacing: 10) {
                    Button(action: {
                        bluetoothManager.startScanning()
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Scan")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    
                    Button(action: {
                        bluetoothManager.stopScanning()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("Stop")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}

// MARK: - Status Cards
struct NavigationStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Navigation")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.navigationActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(status.navigationActive ? "Active" : "Standby")
                        .font(.caption)
                        .foregroundColor(status.navigationActive ? .green : .orange)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "location.north.fill")
                            .foregroundColor(.blue)
                        Text("Heading: \(status.heading, specifier: "%.1f")°")
                            .font(.caption)
                    }
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundColor(.green)
                        Text("Bearing: \(status.bearing, specifier: "%.1f")°")
                            .font(.caption)
                    }
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(.orange)
                        Text("Distance: \(status.distanceText)")
                            .font(.caption)
                    }
                }
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

struct GPSStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPS Status")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                Circle()
                    .fill(status.hasGpsFix ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(status.hasGpsFix ? "Fix" : "No Fix")
                    .font(.caption)
                    .foregroundColor(status.hasGpsFix ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "dot.radiowaves.up")
                        .foregroundColor(.blue)
                    Text("Satellites: \(status.satellites)")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Lat: \(status.currentLat, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Lon: \(status.currentLon, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "mountain.2.fill")
                        .foregroundColor(.brown)
                    Text("Alt: \(status.altitude, specifier: "%.1f") m")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(status.hasGpsFix ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

struct TargetStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Waypoint")
                .font(.callout)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text("Lat: \(status.targetLat, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text("Lon: \(status.targetLon, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

struct EnhancedCompassView: View {
    let heading: Float
    let bearing: Float
    @State private var animatedHeading: Double = 0
    @State private var animatedBearing: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.1)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            ForEach(0..<8) { i in
                let angle = Double(i) * 45
                VStack {
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.black : Color.gray)
                        .frame(width: i % 2 == 0 ? 1.5 : 1, height: i % 2 == 0 ? 8 : 6)
                    Spacer()
                }
                .rotationEffect(.degrees(angle))
            }
            
            VStack {
                Text("N")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
            }
            
            Group {
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 40))
                    let endX = 40 + 28 * sin(animatedHeading * .pi / 180)
                    let endY = 40 - 28 * cos(animatedHeading * .pi / 180)
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Color.blue.opacity(0.3), radius: 1, x: 0, y: 1)
                
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 40))
                    let endX = 40 + 20 * sin(animatedBearing * .pi / 180)
                    let endY = 40 - 20 * cos(animatedBearing * .pi / 180)
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: Color.red.opacity(0.3), radius: 1, x: 0, y: 1)
            }
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white, Color.black]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 3
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
        .onAppear {
            animatedHeading = Double(heading)
            animatedBearing = Double(bearing)
        }
        .onChange(of: heading) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedHeading = Double(newValue)
            }
        }
        .onChange(of: bearing) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedBearing = Double(newValue)
            }
        }
    }
}