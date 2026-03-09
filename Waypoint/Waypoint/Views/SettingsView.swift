import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @ObservedObject var dataStore = DataStore.shared
    
    @State private var showingCalibrationSheet = false
    
    var body: some View {
        List {
            calibrationSection
            northCalibrationSection
            deviceSection
            spotLockSection
            dataSection
            aboutSection
        }
        .sheet(isPresented: $showingCalibrationSheet) {
            CalibrationView()
        }
    }
    
    // MARK: - Calibration Section
    
    private var calibrationSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compass Calibration")
                        .font(.headline)
                    if dataStore.calibration.isCalibrated,
                       let dateCalibrated = dataStore.calibration.dateCalibrated {
                        Text("Last calibrated: \(dateCalibrated, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(dataStore.calibration.sampleCount) samples")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not calibrated!")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Circle()
                    .fill(dataStore.calibration.isCalibrated ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
            }
            
            if dataStore.calibration.isCalibrated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offsets: X=\(dataStore.calibration.offsetX, specifier: "%.2f"), Y=\(dataStore.calibration.offsetY, specifier: "%.2f"), Z=\(dataStore.calibration.offsetZ, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Scales: X=\(dataStore.calibration.scaleX, specifier: "%.3f"), Y=\(dataStore.calibration.scaleY, specifier: "%.3f"), Z=\(dataStore.calibration.scaleZ, specifier: "%.3f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                showingCalibrationSheet = true
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text(dataStore.calibration.isCalibrated ? "Recalibrate Compass" : "Calibrate Compass")
                }
            }
            .disabled(bluetooth.connectionState != .connected)
            
            if dataStore.calibration.isCalibrated {
                Button {
                    bluetooth.sendCalibrationValues(dataStore.calibration)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                        Text("Send to Helm")
                    }
                }
                .disabled(bluetooth.connectionState != .connected)
            }
        } header: {
            Text("Compass")
        } footer: {
            Text("Calibration improves compass accuracy by correcting for magnetic interference. Rotate the Helm device slowly during calibration.")
        }
    }
    
    // MARK: - North Calibration Section
    
    private var northCalibrationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("North Alignment")
                            .font(.headline)
                        if dataStore.calibration.headingOffset != 0 {
                            Text("Offset: \(dataStore.calibration.headingOffset, specifier: "%.1f")°")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not calibrated")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(dataStore.calibration.headingOffset != 0 ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)
                }
                
                if let heading = bluetooth.sensorData?.heading {
                    HStack {
                        Text("Current Heading:")
                            .font(.subheadline)
                        Spacer()
                        Text("\(heading, specifier: "%.1f")°")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Button {
                Task {
                    await calibrateNorth()
                }
            } label: {
                HStack {
                    Image(systemName: "location.north.circle")
                    Text("Calibrate North")
                }
            }
            .disabled(bluetooth.connectionState != .connected || bluetooth.sensorData == nil)
            
            if dataStore.calibration.headingOffset != 0 {
                Button(role: .destructive) {
                    var cal = dataStore.calibration
                    cal.headingOffset = 0
                    dataStore.updateCalibration(cal)
                    bluetooth.sendCalibrationValues(cal)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset North Offset")
                    }
                }
                .disabled(bluetooth.connectionState != .connected)
            }
        } header: {
            Text("North Calibration")
        } footer: {
            Text("Point the Helm device directly north (use a compass app), then tap 'Calibrate North' to set 0° heading.")
        }
    }
    
    // MARK: - Spot Lock Section

    private var spotLockSection: some View {
        Section {
            NavigationLink {
                SpotLockSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pin.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spot Lock")
                        Text("Position holding parameters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !dataStore.spotLockSettings.isAllDefault {
                        Text("Modified")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        } header: {
            Text("Navigation")
        }
    }

    // MARK: - Device Section
    
    private var deviceSection: some View {
        Section {
            HStack {
                Text("Connection Status")
                Spacer()
                Text(bluetooth.connectionState.rawValue)
                    .foregroundColor(.secondary)
            }
            
            if bluetooth.connectionState == .disconnected {
                Button("Connect to Helm") {
                    bluetooth.startScanning()
                }
            } else if bluetooth.connectionState == .connected {
                Button("Disconnect") {
                    bluetooth.disconnect()
                }
                .foregroundColor(Color.red)
            }
        } header: {
            Text("Helm Device")
        }
    }
    
    // MARK: - Data Section
    
    private var dataSection: some View {
        Section {
            if dataStore.calibration.isCalibrated {
                Button(role: .destructive) {
                    dataStore.clearCalibration()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Calibration")
                    }
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Calibration data is saved automatically and persists across app updates.")
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("AutoHelm")
                    .font(.title2.bold())
                
                Text("GPS Navigation System for Autonomous Boat Control")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Features")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    FeatureRow(icon: "pin.fill", text: "Spot Lock position holding")
                    FeatureRow(icon: "safari.fill", text: "Compass-guided steering")
                    FeatureRow(icon: "antenna.radiowaves.left.and.right", text: "Wireless motor control")
                }
                
                Divider()
                
                Text("System Components")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    ComponentRow(name: "ESP32 DevKit", desc: "Main controller")
                    ComponentRow(name: "U-blox NEO-6M", desc: "GPS module")
                    ComponentRow(name: "MMC5603", desc: "Magnetometer")
                    ComponentRow(name: "CC1101", desc: "433MHz RF transceiver")
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Support & Issues")
                        .font(.headline)
                    
                    Text("Found a bug or have a feature request?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let githubUrl = URL(string: "https://github.com/brentonford/AutoHelm") {
                        Link(destination: githubUrl) {
                            HStack {
                                Image(systemName: "link")
                                Text("Report on GitHub")
                                Spacer()
                                Image(systemName: "arrow.up.forward")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Version")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("2.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("License")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("MIT License")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("About")
        }
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func calibrateNorth() async {
        guard let currentHeading = await bluetooth.getCurrentHeading() else {
            print("[Settings] Failed to get current heading")
            return
        }
        
        print("[Settings] Current heading: \(currentHeading)°, setting as north offset")
        bluetooth.setHeadingOffset(currentHeading)
    }
}

// MARK: - Calibration View

struct CalibrationView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @ObservedObject var dataStore = DataStore.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var calibrationStarted = false
    @State private var showingSaveConfirmation = false
    
    private var canSave: Bool {
        guard let data = bluetooth.calibrationData else { return false }
        return (data.samples ?? 0) >= 50
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                instructionsSection
                statusSection
                visualizationSection
                Spacer()
                actionButtons
            }
            .padding()
            .navigationTitle("Compass Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if bluetooth.isCalibrating {
                            bluetooth.stopCalibration()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Instructions", systemImage: "info.circle")
                .font(.headline)
            
            Text("1. Place the Helm device on a flat surface")
            Text("2. Tap 'Start Calibration'")
            Text("3. Slowly rotate the device 360° in a circle")
            Text("4. Keep the device level during rotation")
            Text("5. Tap 'Stop & Save' when complete")
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status:")
                    .font(.headline)
                Spacer()
                Text(bluetooth.isCalibrating ? "Calibrating..." : "Ready")
                    .foregroundColor(bluetooth.isCalibrating ? .orange : .green)
            }
            
            if let data = bluetooth.calibrationData {
                HStack {
                    Text("Samples:")
                    Spacer()
                    Text("\(data.samples ?? 0)")
                        .font(.headline)
                        .foregroundColor((data.samples ?? 0) >= 50 ? .green : .orange)
                }
                
                if (data.samples ?? 0) > 0 {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calculated Values:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Offset X: \(data.offsetX, specifier: "%.2f")")
                                Text("Offset Y: \(data.offsetY, specifier: "%.2f")")
                                Text("Offset Z: \(data.offsetZ, specifier: "%.2f")")
                            }
                            .font(.caption)
                            
                            Spacer()
                            
                            VStack(alignment: .leading) {
                                Text("Scale X: \(data.scaleX, specifier: "%.3f")")
                                Text("Scale Y: \(data.scaleY, specifier: "%.3f")")
                                Text("Scale Z: \(data.scaleZ, specifier: "%.3f")")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var visualizationSection: some View {
        VStack {
            if let data = bluetooth.calibrationData, (data.samples ?? 0) > 0 {
                CalibrationVisualization(data: data)
                    .frame(height: 200)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    Text("Rotate device to\ncollect samples")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if bluetooth.isCalibrating {
                Button {
                    bluetooth.stopCalibration()
                    if canSave {
                        showingSaveConfirmation = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text(canSave ? "Stop & Save" : "Stop Calibration")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(canSave ? .green : .red)
            } else {
                Button {
                    bluetooth.startCalibration()
                    calibrationStarted = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Calibration")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(bluetooth.connectionState != .connected)
            }
            
            if !bluetooth.isCalibrating && canSave {
                Button {
                    showingSaveConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Calibration")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Calibration Visualization

struct CalibrationVisualization: View {
    let data: CalibrationData
    
    private var rangeX: Double {
        guard let minX = data.minX, let maxX = data.maxX else { return 0 }
        return maxX - minX
    }
    
    private var rangeY: Double {
        guard let minY = data.minY, let maxY = data.maxY else { return 0 }
        return maxY - minY
    }
    
    private var normalizedCenterX: Double {
        guard rangeX > 0, let minX = data.minX else { return 0.5 }
        return (data.offsetX - minX) / rangeX
    }
    
    private var normalizedCenterY: Double {
        guard rangeY > 0, let minY = data.minY else { return 0.5 }
        return (data.offsetY - minY) / rangeY
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(width: size, height: size)
                
                if let minX = data.minX, let maxX = data.maxX,
                   let minY = data.minY, let maxY = data.maxY {
                    
                    let scaleX = rangeX > 0 ? (size * 0.9) / rangeX : 1
                    let scaleY = rangeY > 0 ? (size * 0.9) / rangeY : 1
                    let scale = min(scaleX, scaleY)
                    
                    Ellipse()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: rangeX * scale, height: rangeY * scale)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .offset(
                            x: (data.offsetX - (minX + maxX) / 2) * scale,
                            y: (data.offsetY - (minY + maxY) / 2) * scale
                        )
                    
                    Circle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Text("X range: \(rangeX, specifier: "%.1f")")
                        Spacer()
                        Text("Y range: \(rangeY, specifier: "%.1f")")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color.blue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Component Row

struct ComponentRow: View {
    let name: String
    let desc: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(BluetoothManager())
    }
}