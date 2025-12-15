import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    let selectedWaypoint: Waypoint?
    
    @State private var navigationEnabled = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            connectionSection
            gpsStatusSection
            navigationSection
            waypointSection
        }
        .navigationTitle("Helm Control")
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: bluetooth.lastError) { _, error in
            if let error = error {
                errorMessage = error
                showingError = true
                isLoading = false
            }
        }
        .onChange(of: bluetooth.lastResponse) { _, response in
            isLoading = false
        }
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                connectionIndicator
                Text(bluetooth.connectionState.rawValue)
                Spacer()
                if bluetooth.connectionState == .disconnected {
                    Button("Connect") {
                        bluetooth.startScanning()
                    }
                }
            }
        }
    }
    
    private var connectionIndicator: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 12, height: 12)
    }
    
    private var connectionColor: Color {
        switch bluetooth.connectionState {
        case .connected: return .green
        case .connecting, .scanning: return .orange
        case .disconnected: return .red
        }
    }
    
    // MARK: - GPS Status Section
    
    private var gpsStatusSection: some View {
        Section("GPS Status") {
            if let status = bluetooth.deviceStatus {
                LabeledContent("Fix") {
                    HStack {
                        Circle()
                            .fill(status.hasFix ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(status.hasFix ? "Valid" : "No Fix")
                    }
                }
                
                LabeledContent("Satellites", value: "\(status.satellites)")
                LabeledContent("HDOP", value: String(format: "%.1f", status.hdop))
                
                if status.hasFix {
                    LabeledContent("Position") {
                        Text(String(format: "%.6f, %.6f",
                                    status.currentLat, status.currentLon))
                        .font(.caption)
                    }
                    
                    LabeledContent("Heading", value: String(format: "%.1f°", status.heading))
                }
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Navigation Section
    
    private var navigationSection: some View {
        Section("Navigation") {
            if let status = bluetooth.deviceStatus {
                if status.hasTarget == true {
                    LabeledContent("Distance", value: formatDistance(status.distance))
                    LabeledContent("Bearing", value: String(format: "%.1f°", status.bearing))
                    
                    if let relative = status.relative {
                        LabeledContent("Correction") {
                            HStack {
                                Text(correctionDirection(relative))
                                Text(String(format: "%+.1f°", relative))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let target = status.targetLocation {
                        LabeledContent("Target") {
                            Text(String(format: "%.6f, %.6f", target.latitude, target.longitude))
                                .font(.caption)
                        }
                    }
                } else {
                    Text("No target waypoint set")
                        .foregroundColor(.secondary)
                }
            }
            
            Toggle("Navigation Enabled", isOn: $navigationEnabled)
                .disabled(!canEnableNavigation)
                .onChange(of: navigationEnabled) { _, enabled in
                    toggleNavigation(enabled)
                }
        }
    }
    
    private func correctionDirection(_ relative: Double) -> String {
        if abs(relative) <= 15.0 {
            return "✓ On course"
        }
        return relative > 0 ? "→ Turn RIGHT" : "← Turn LEFT"
    }
    
    private var canEnableNavigation: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let status = bluetooth.deviceStatus else { return false }
        return status.hasFix && status.hdop < 5.0
    }
    
    // MARK: - Waypoint Section
    
    private var waypointSection: some View {
        Section("Waypoint") {
            if let waypoint = selectedWaypoint {
                LabeledContent("Selected") {
                    Text(waypoint.name)
                }
                
                LabeledContent("Coordinates") {
                    Text(String(format: "%.6f, %.6f",
                                waypoint.coordinate.latitude,
                                waypoint.coordinate.longitude))
                    .font(.caption)
                }
                
                Button {
                    sendWaypoint(waypoint)
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Send to Helm")
                    }
                }
                .disabled(bluetooth.connectionState != .connected || isLoading)
            } else {
                Text("No waypoint selected")
                    .foregroundColor(.secondary)
                Text("Tap on the map to create a waypoint")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleNavigation(_ enabled: Bool) {
        isLoading = true
        if enabled {
            bluetooth.enableNavigation()
        } else {
            bluetooth.disableNavigation()
        }
    }
    
    private func sendWaypoint(_ waypoint: Waypoint) {
        isLoading = true
        bluetooth.sendWaypoint(waypoint)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}