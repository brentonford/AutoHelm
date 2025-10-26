import SwiftUI
import MapKit
import CoreLocation

// MARK: - Combined Settings View (Calibration + Offline)
struct CombinedSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @State private var selectedSection = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    Text("Calibration").tag(0)
                    Text("Offline Maps").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedSection == 0 {
                    CalibrationView(bluetoothManager: bluetoothManager)
                } else {
                    OfflineMapsView(locationManager: locationManager, offlineTileManager: offlineTileManager)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Calibration View
struct CalibrationView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showCalibrationComplete = false
    @State private var currentStep = 1
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !bluetoothManager.isConnected {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Connect to Helm Device")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Please connect to your Helm device in the Helm tab before calibrating the magnetometer.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Text("Magnetometer Calibration")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Follow these steps to calibrate your compass for accurate navigation.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    if !bluetoothManager.isCalibrating {
                        CalibrationInstructions()
                        
                        Button(action: {
                            bluetoothManager.startCalibration()
                            currentStep = 1
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Start Calibration")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    } else {
                        CalibrationActiveView(
                            magnetometerData: bluetoothManager.magnetometerData,
                            onSave: { data in
                                bluetoothManager.saveCalibration(data)
                                showCalibrationComplete = true
                            },
                            onDiscard: {
                                bluetoothManager.stopCalibration()
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Compass Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Calibration Complete", isPresented: $showCalibrationComplete) {
            Button("OK") {
                showCalibrationComplete = false
            }
        } message: {
            Text("Magnetometer calibration has been saved to the Helm device. Your compass should now be more accurate.")
        }
    }
}

struct CalibrationInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibration Steps:")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 12) {
                CalibrationStep(number: 1, text: "Tap 'Start Calibration' to begin")
                CalibrationStep(number: 2, text: "Hold the Helm device steady")
                CalibrationStep(number: 3, text: "Slowly rotate the device in all directions")
                CalibrationStep(number: 4, text: "Continue for 60-90 seconds")
                CalibrationStep(number: 5, text: "Tap 'Save' when readings stabilize")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Important Tips:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                
                Text("• Stay away from metal objects and electronics")
                    .font(.caption)
                Text("• Rotate slowly and smoothly in figure-8 patterns")
                    .font(.caption)
                Text("• Ensure all axes (X, Y, Z) show movement")
                    .font(.caption)
                Text("• Calibrate outdoors for best results")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct CalibrationStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}

struct CalibrationActiveView: View {
    let magnetometerData: MagnetometerData?
    let onSave: (MagnetometerData) -> Void
    let onDiscard: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Calibration in Progress")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Rotate the Helm device slowly in all directions")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let data = magnetometerData {
                VStack(spacing: 16) {
                    MagnetometerReadingsView(data: data)
                    CalibrationProgressView(data: data)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button(action: onDiscard) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Discard")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: { onSave(data) }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("Waiting for magnetometer data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct MagnetometerReadingsView: View {
    let data: MagnetometerData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Readings")
                .font(.headline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("X: \(data.x, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                    Text("Y: \(data.y, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                    Text("Z: \(data.z, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Range X: \(data.maxX - data.minX, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Range Y: \(data.maxY - data.minY, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Range Z: \(data.maxZ - data.minZ, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CalibrationProgressView: View {
    let data: MagnetometerData
    
    private var progress: Double {
        let rangeX = data.maxX - data.minX
        let rangeY = data.maxY - data.minY
        let rangeZ = data.maxZ - data.minZ
        let avgRange = (rangeX + rangeY + rangeZ) / 3.0
        return min(Double(avgRange) / 100.0, 1.0)
    }
    
    private var isCalibrationGood: Bool {
        progress > 0.7
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calibration Progress")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                if isCalibrationGood {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: isCalibrationGood ? .green : .blue))
            
            Text(isCalibrationGood ? "Ready to save calibration" : "Keep rotating in all directions")
                .font(.caption)
                .foregroundColor(isCalibrationGood ? .green : .secondary)
        }
    }
}

// MARK: - Offline Maps View
struct OfflineMapsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @StateObject private var waypointManager = WaypointManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var radiusKm: Double = 5.0
    @State private var selectedCenter: CLLocationCoordinate2D?
    @State private var showDownloadAlert = false
    @State private var editingRegionId: UUID?
    @State private var editingRegionName: String = ""
    @State private var showDeleteAlert = false
    @State private var regionToDelete: Int?
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position) {
                        UserAnnotation()
                        
                        ForEach(waypointManager.savedWaypoints) { waypoint in
                            Annotation("", coordinate: waypoint.coordinate) {
                                VStack(spacing: 0) {
                                    Image(systemName: waypoint.iconName)
                                        .font(.system(size: 8))
                                        .foregroundColor(.yellow)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                    Text(waypoint.name)
                                        .font(.system(size: 6))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.yellow.opacity(0.8))
                                        .cornerRadius(2)
                                }
                            }
                        }
                        
                        ForEach(offlineTileManager.downloadedRegions) { region in
                            MapCircle(center: region.center, radius: region.radiusKm * 1000)
                                .foregroundStyle(Color.green.opacity(0.2))
                                .stroke(Color.green, lineWidth: 2)
                            
                            Annotation("", coordinate: region.center) {
                                VStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                    Text(region.name)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        if let center = selectedCenter {
                            MapCircle(center: center, radius: radiusKm * 1000)
                                .foregroundStyle(Color.blue.opacity(0.2))
                                .stroke(Color.blue, lineWidth: 2)
                            
                            Annotation("", coordinate: center) {
                                VStack(spacing: 2) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.blue)
                                    }
                                    Text("\(radiusKm, specifier: "%.1f") km")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .mapStyle(.hybrid)
                    .frame(height: 300)
                    .onTapGesture { screenCoordinate in
                        if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                            selectedCenter = coordinate
                        }
                    }
                }
                
                if selectedCenter == nil && offlineTileManager.downloadedRegions.isEmpty && waypointManager.savedWaypoints.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "hand.tap.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Tap map to select download area")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
                }
            }
            
            ScrollView {
                VStack(spacing: 16) {
                    if let center = selectedCenter {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected Location")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("Lat: \(center.latitude, specifier: "%.6f")")
                                .font(.system(.caption, design: .monospaced))
                            Text("Lon: \(center.longitude, specifier: "%.6f")")
                                .font(.system(.caption, design: .monospaced))
                            
                            Button(action: {
                                selectedCenter = nil
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                    Text("Clear Selection")
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Download Radius: \(radiusKm, specifier: "%.1f") km")
                            .font(.callout)
                            .fontWeight(.medium)
                        
                        Slider(value: $radiusKm, in: 1.0...20.0, step: 1.0)
                        
                        Text("Larger areas require more storage and time")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    
                    if offlineTileManager.isDownloading {
                        VStack(spacing: 8) {
                            ProgressView(value: offlineTileManager.downloadProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text("\(offlineTileManager.downloadedTilesCount) / \(offlineTileManager.totalTilesCount) tiles")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                offlineTileManager.cancelDownload()
                            }) {
                                Text("Cancel Download")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    } else {
                        Button(action: {
                            showDownloadAlert = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Maps for Selected Area")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedCenter != nil ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(selectedCenter == nil)
                        .padding(.horizontal, 12)
                    }
                    
                    Button(action: {
                        offlineTileManager.clearCache()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All Cached Maps")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Offline Maps")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Download Maps", isPresented: $showDownloadAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Download") {
                if let center = selectedCenter {
                    let kmToDegrees = radiusKm / 111.0
                    let region = MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: kmToDegrees, longitudeDelta: kmToDegrees)
                    )
                    offlineTileManager.downloadTiles(region: region, minZoom: 10, maxZoom: 15) { regionId in
                        offlineTileManager.fetchLocationName(for: center) { locationName in
                            offlineTileManager.updateRegionName(id: regionId, name: locationName)
                        }
                    }
                    selectedCenter = nil
                }
            }
        } message: {
            Text("Download maps for \(radiusKm, specifier: "%.1f") km radius around selected location? This may take several minutes.")
        }
    }
}