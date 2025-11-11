import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var offlineTileManager: OfflineTileManager
    @EnvironmentObject var clusteringManager: AnnotationClusteringManager
    @StateObject private var logger = AppLogger.shared
    
    @State private var showingClearCacheAlert = false
    @State private var showingLogLevelPicker = false
    
    var body: some View {
        NavigationView {
            List {
                // Map Settings Section
                Section("Map Settings") {
                    HStack {
                        Image(systemName: "map.circle")
                            .foregroundColor(.blue)
                        Text("Annotation Clustering")
                        Spacer()
                        Toggle("", isOn: $clusteringManager.clusteringEnabled)
                    }
                    
                    if clusteringManager.clusteringEnabled {
                        VStack {
                            HStack {
                                Image(systemName: "scope")
                                    .foregroundColor(.blue)
                                Text("Cluster Radius")
                                Spacer()
                                Text("\(Int(clusteringManager.clusterRadius))m")
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $clusteringManager.clusterRadius, in: 50...500, step: 10)
                                .onChange(of: clusteringManager.clusterRadius) { _, newValue in
                                    clusteringManager.updateClusterRadius(newValue)
                                }
                        }
                    }
                }
                
                // Offline Maps Section
                Section("Offline Maps") {
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Cache Size")
                            Text(offlineTileManager.getFormattedCacheSize())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "map")
                            .foregroundColor(.green)
                        Text("Downloaded Regions")
                        Spacer()
                        Text("\(offlineTileManager.downloadedRegions.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        showingClearCacheAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Clear Offline Cache")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Logging Settings Section
                Section("Logging & Debug") {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.orange)
                        Text("Log Level")
                        Spacer()
                        Text(logger.currentLogLevel.rawValue)
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        showingLogLevelPicker = true
                    }
                    
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.orange)
                        Text("Remote Logging")
                        Spacer()
                        Toggle("", isOn: $logger.isRemoteLoggingEnabled)
                    }
                    
                    Button("Clear Performance Metrics") {
                        logger.clearPerformanceMetrics()
                    }
                    .foregroundColor(.orange)
                }
                
                // App Info Section
                Section("App Information") {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Version")
                        Spacer()
                        Text(getAppVersion())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "hammer")
                            .foregroundColor(.blue)
                        Text("Build")
                        Spacer()
                        Text(getBuildNumber())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Clear Offline Cache", isPresented: $showingClearCacheAlert) {
            Button("Clear", role: .destructive) {
                Task {
                    await offlineTileManager.clearCache()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all downloaded map tiles. You'll need to download them again for offline use.")
        }
        .sheet(isPresented: $showingLogLevelPicker) {
            LogLevelPickerView()
        }
    }
    
    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

struct LogLevelPickerView: View {
    @StateObject private var logger = AppLogger.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    HStack {
                        Text("\(level.emoji) \(level.rawValue)")
                        Spacer()
                        if logger.currentLogLevel == level {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        logger.setLogLevel(level)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Log Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BluetoothSettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        NavigationView {
            List {
                Section("Connection Status") {
                    HStack {
                        Circle()
                            .fill(bluetoothManager.isConnected ? .green : .red)
                            .frame(width: 16, height: 16)
                        Text(bluetoothManager.isConnected ? "Connected" : "Disconnected")
                        Spacer()
                        if bluetoothManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                
                Section("Device Information") {
                    if let status = bluetoothManager.deviceStatus {
                        HStack {
                            Text("GPS Fix")
                            Spacer()
                            Text(status.hasGpsFix ? "Yes" : "No")
                                .foregroundColor(status.hasGpsFix ? .green : .red)
                        }
                        
                        HStack {
                            Text("Satellites")
                            Spacer()
                            Text("\(status.satellites)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Accuracy")
                            Spacer()
                            Text(status.gpsAccuracyDescription)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No device information available")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "helm")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Waypoint Navigation")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("GPS Navigation & Waypoint Management")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "map", title: "Advanced Mapping", description: "MapKit integration with offline tile support and custom annotations")
                        
                        FeatureRow(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth Connectivity", description: "Real-time communication with helm navigation device")
                        
                        FeatureRow(icon: "location.viewfinder", title: "Precise Navigation", description: "High-accuracy GPS with structured logging and performance metrics")
                        
                        FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Performance Monitoring", description: "Built-in analytics and remote logging capabilities")
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(OfflineTileManager())
        .environmentObject(AnnotationClusteringManager())
}