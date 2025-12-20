import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @AppStorage("autoEnableNavigation") private var autoEnableNavigation = true
    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap = true
    @AppStorage("useMetricUnits") private var useMetricUnits = true
    
    var body: some View {
        List {
            navigationSettingsSection
            displaySettingsSection
            deviceSection
            aboutSection
        }
        .navigationTitle("Settings")
    }
    
    // MARK: - Navigation Settings
    
    private var navigationSettingsSection: some View {
        Section {
            Toggle("Auto-enable navigation when sending waypoint", isOn: $autoEnableNavigation)
        } header: {
            Text("Navigation")
        } footer: {
            Text("When enabled, sending a waypoint to Helm will automatically enable autonomous navigation.")
        }
    }
    
    // MARK: - Display Settings
    
    private var displaySettingsSection: some View {
        Section {
            Toggle("Show coordinates on map markers", isOn: $showCoordinatesOnMap)
            Toggle("Use metric units", isOn: $useMetricUnits)
        } header: {
            Text("Display")
        } footer: {
            Text("Metric: meters and kilometers • Imperial: feet and miles")
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
                .foregroundColor(.red)
            }
        } header: {
            Text("Helm Device")
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
                    FeatureRow(icon: "location.fill", text: "Autonomous GPS navigation")
                    FeatureRow(icon: "safari.fill", text: "Compass-guided steering")
                    FeatureRow(icon: "map.fill", text: "Waypoint management")
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
                    
                    Link(destination: URL(string: "https://github.com/brentonford/AutoHelm")!) {
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
                
                Divider()
                
                HStack {
                    Text("Version")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("1.0.0")
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
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
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