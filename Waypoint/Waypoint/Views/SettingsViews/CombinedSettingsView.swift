import SwiftUI
import MapKit

struct CombinedSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    
    var body: some View {
        NavigationView {
            List {
                Section("Connection") {
                    NavigationLink("Bluetooth", destination: BluetoothSettingsView(bluetoothManager: bluetoothManager))
                    NavigationLink("Calibration", destination: CalibrationView(bluetoothManager: bluetoothManager))
                    NavigationLink("RF Remote", destination: RFRemoteSettingsView(bluetoothManager: bluetoothManager))
                }
                
                Section("Maps & Data") {
                    NavigationLink("Offline Maps", destination: OfflineMapsView(offlineTileManager: offlineTileManager))
                    NavigationLink("Waypoint Management", destination: WaypointManagementView())
                }
                
                Section("System") {
                    NavigationLink("About", destination: AboutView())
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Bluetooth Settings View
struct BluetoothSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        List {
            Section("Connection Status") {
                ConnectionSectionView(bluetoothManager: bluetoothManager)
            }
            
            if bluetoothManager.isConnected {
                Section("Device Information") {
                    DeviceInfoSection(bluetoothManager: bluetoothManager)
                }
            }
        }
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Device Info Section
struct DeviceInfoSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Signal Strength")
                Spacer()
                Text("\(bluetoothManager.signalStrength) dBm")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Connection Status")
                Spacer()
                Text(bluetoothManager.connectionStatus)
                    .foregroundColor(bluetoothManager.isConnected ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Calibration View
struct CalibrationView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isCalibrating = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CalibrationInstructionsCard()
                
                if bluetoothManager.isConnected {
                    CalibrationControlsSection(
                        bluetoothManager: bluetoothManager,
                        isCalibrating: $isCalibrating
                    )
                    
                    if let magnetometerData = bluetoothManager.magnetometerData {
                        MagnetometerDataCard(data: magnetometerData)
                    }
                } else {
                    DisconnectedWarningCard()
                }
            }
            .padding()
        }
        .navigationTitle("Compass Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Calibration Components
struct CalibrationInstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration Instructions")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(number: 1, text: "Ensure Helm device is connected")
                InstructionRow(number: 2, text: "Tap 'Start Calibration' below")
                InstructionRow(number: 3, text: "Slowly rotate device in all directions")
                InstructionRow(number: 4, text: "Continue for 2-3 minutes until readings stabilize")
                InstructionRow(number: 5, text: "Tap 'Save Calibration' when complete")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundColor(.blue)
                .fontWeight(.medium)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
        }
    }
}

struct CalibrationControlsSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isCalibrating: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if !isCalibrating {
                Button(action: startCalibration) {
                    Text("Start Calibration")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                VStack(spacing: 8) {
                    Button(action: saveCalibration) {
                        Text("Save Calibration")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: stopCalibration) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    private func startCalibration() {
        bluetoothManager.startCalibration()
        isCalibrating = true
    }
    
    private func saveCalibration() {
        if let data = bluetoothManager.magnetometerData {
            bluetoothManager.saveCalibration(data)
        }
        isCalibrating = false
    }
    
    private func stopCalibration() {
        bluetoothManager.stopCalibration()
        isCalibrating = false
    }
}

struct MagnetometerDataCard: View {
    let data: MagnetometerData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Magnetometer Data")
                .font(.headline)
            
            VStack(spacing: 8) {
                DataRow(label: "X", value: data.x, min: data.minX, max: data.maxX)
                DataRow(label: "Y", value: data.y, min: data.minY, max: data.maxY)
                DataRow(label: "Z", value: data.z, min: data.minZ, max: data.maxZ)
            }
        }
        .padding()
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
    }
}

struct DataRow: View {
    let label: String
    let value: Float
    let min: Float
    let max: Float
    
    var body: some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
                .frame(width: 20, alignment: .leading)
            Text("\(value, specifier: "%.2f")")
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text("[\(min, specifier: "%.1f"), \(max, specifier: "%.1f")]")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct DisconnectedWarningCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Helm Device Not Connected")
                .font(.headline)
            Text("Connect to your Helm device to access calibration features")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - RF Remote Settings View
struct RFRemoteSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isPairing = false
    
    var body: some View {
        List {
            Section(header: Text("RF Remote Control")) {
                if bluetoothManager.isConnected {
                    RFRemotePairingSection(
                        bluetoothManager: bluetoothManager,
                        isPairing: $isPairing
                    )
                } else {
                    Text("Connect to Helm device to configure RF remote")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Information")) {
                RFRemoteInfoSection()
            }
        }
        .navigationTitle("RF Remote")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RFRemotePairingSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isPairing: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if !isPairing {
                Button(action: startPairing) {
                    Text("Start RF Pairing")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                VStack(spacing: 8) {
                    Text("RF Pairing Mode Active")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    Text("Press and hold the pairing button on your RF remote now")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 8) {
                        Button("Complete") {
                            bluetoothManager.completeRFRemotePairing()
                            isPairing = false
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Cancel") {
                            bluetoothManager.cancelRFRemotePairing()
                            isPairing = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }
    
    private func startPairing() {
        bluetoothManager.startRFRemotePairing()
        isPairing = true
    }
}

struct RFRemoteInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The RF remote system allows the Helm device to control compatible trolling motors wirelessly.")
                .font(.caption)
            Text("Supported Models:")
                .font(.caption)
                .fontWeight(.medium)
            Text("• Watersnake Fierce 2")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Offline Maps View
struct OfflineMapsView: View {
    @ObservedObject var offlineTileManager: OfflineTileManager
    @State private var selectedRegion: MKCoordinateRegion?
    @State private var showDownloadSheet = false
    
    var body: some View {
        List {
            Section(header: Text("Storage")) {
                HStack {
                    Text("Cache Size")
                    Spacer()
                    Text(offlineTileManager.cacheSizeString)
                        .foregroundColor(.secondary)
                }
                
                Button("Clear All Cached Maps") {
                    offlineTileManager.clearCache()
                }
                .foregroundColor(.red)
            }
            
            Section(header: Text("Downloaded Regions")) {
                if offlineTileManager.downloadedRegions.isEmpty {
                    Text("No offline maps downloaded")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(Array(offlineTileManager.downloadedRegions.enumerated()), id: \.element.id) { index, region in
                        OfflineRegionRow(region: region) {
                            offlineTileManager.deleteRegion(at: index)
                        }
                    }
                }
            }
            
            Section(header: Text("Download Progress")) {
                if offlineTileManager.isDownloading {
                    DownloadProgressView(offlineTileManager: offlineTileManager)
                } else {
                    Text("No active downloads")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .navigationTitle("Offline Maps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OfflineRegionRow: View {
    let region: DownloadedRegion
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(region.name)
                    .font(.subheadline)
                Spacer()
                Button("Delete", action: onDelete)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                Text("Radius: \(region.radiusKm, specifier: "%.1f") km")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(region.downloadDate.timeAgoString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DownloadProgressView: View {
    @ObservedObject var offlineTileManager: OfflineTileManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading...")
                    .font(.subheadline)
                Spacer()
                Button("Cancel") {
                    offlineTileManager.cancelDownload()
                }
                .foregroundColor(.red)
                .font(.caption)
            }
            
            ProgressView(value: offlineTileManager.downloadProgress)
            
            Text("\(offlineTileManager.downloadedTilesCount) of \(offlineTileManager.totalTilesCount) tiles")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Waypoint Management View
struct WaypointManagementView: View {
    var body: some View {
        List {
            Section(header: Text("Import/Export")) {
                Button("Export All Waypoints") {
                    // TODO: Implement waypoint export
                }
                
                Button("Import Waypoints") {
                    // TODO: Implement waypoint import
                }
            }
            
            Section(header: Text("Settings")) {
                HStack {
                    Text("Default Icon")
                    Spacer()
                    Text("📍")
                }
                
                Toggle("Auto-save Sent Waypoints", isOn: .constant(true))
            }
        }
        .navigationTitle("Waypoint Management")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        List {
            Section(header: Text("Application")) {
                AboutRow(label: "Version", value: "1.0.0")
                AboutRow(label: "Build", value: "1")
            }
            
            Section(header: Text("System")) {
                AboutRow(label: "Helm Device", value: "Arduino UNO R4 WiFi")
                AboutRow(label: "RF Frequency", value: "433.032 MHz")
                AboutRow(label: "BLE Protocol", value: "Custom GPS Protocol")
            }
            
            Section(header: Text("Features")) {
                FeatureRow(title: "GPS Navigation", description: "Real-time waypoint guidance")
                FeatureRow(title: "Offline Maps", description: "Download OpenStreetMap tiles")
                FeatureRow(title: "Compass Calibration", description: "Magnetometer calibration system")
                FeatureRow(title: "RF Control", description: "Wireless motor control via 433MHz")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct FeatureRow: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}