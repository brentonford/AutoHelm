import SwiftUI
import MapKit

struct HelmControlView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @StateObject private var locationManager = LocationManager()
    @State private var navigationState: NavigationToggleState = .idle
    @State private var previousNavigationEnabled = false
    @State private var showingNavigationAlert = false
    @State private var alertMessage = ""
    
    // Navigation state machine
    enum NavigationToggleState: Equatable {
        case idle
        case enabling
        case enabled
        case disabling
        case error(String)
        
        var isProcessing: Bool {
            switch self {
            case .enabling, .disabling: return true
            default: return false
            }
        }
        
        var isEnabled: Bool {
            switch self {
            case .enabled: return true
            default: return false
            }
        }
        
        static func == (lhs: NavigationToggleState, rhs: NavigationToggleState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.enabling, .enabling), (.enabled, .enabled), (.disabling, .disabling):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
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
                    
                    // Navigation Control - Enhanced with Toggle
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
                syncNavigationState()
            }
            .onChange(of: bluetoothManager.deviceStatus?.hasGpsFix) { oldValue, newValue in
                handleGpsFixChange(newValue)
            }
            .onChange(of: bluetoothManager.isConnected) { oldValue, newValue in
                handleConnectionChange(newValue)
            }
            .alert("Navigation Control", isPresented: $showingNavigationAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
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
                    
                    // DOP indicator for navigation safety
                    if let hdop = status.hdop {
                        statusRow("HDOP", value: String(format: "%.1f", hdop), color: hdop < 5.0 ? .green : .orange)
                    }
                    
                    if status.hasGpsFix {
                        statusRow("Position", value: "\(String(format: "%.6f", status.currentLat)), \(String(format: "%.6f", status.currentLon))")
                        statusRow("Altitude", value: "\(String(format: "%.1f", status.altitude))m")
                        statusRow("Heading", value: "\(String(format: "%.1f", status.heading))°")
                    }
                    
                    if let target = status.targetCoordinate {
                        Divider()
                        HStack {
                            Text("Navigation Active")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            // Navigation state indicator
                            Circle()
                                .fill(navigationState.isEnabled ? .green : .gray)
                                .frame(width: 12, height: 12)
                        }
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
            
            VStack(spacing: 16) {
                // Enhanced Navigation Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Navigation")
                            .font(.headline)
                        Text(navigationStatusText)
                            .font(.caption)
                            .foregroundColor(navigationStatusColor)
                    }
                    
                    Spacer()
                    
                    if navigationState.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("Navigation", isOn: Binding(
                            get: { navigationState.isEnabled },
                            set: { _ in toggleNavigation() }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .disabled(!canToggleNavigation)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Safety requirements display
                VStack(alignment: .leading, spacing: 8) {
                    Text("Safety Requirements")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    requirementRow("Device Connected", satisfied: bluetoothManager.isConnected)
                    requirementRow("GPS Fix Valid", satisfied: bluetoothManager.deviceStatus?.hasGpsFix == true)
                    requirementRow("DOP < 5.0", satisfied: isDopValid)
                    requirementRow("Waypoint Set", satisfied: bluetoothManager.deviceStatus?.targetCoordinate != nil)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private var navigationStatusText: String {
        switch navigationState {
        case .idle:
            return "Ready to navigate"
        case .enabling:
            return "Enabling navigation..."
        case .enabled:
            return "Navigation active"
        case .disabling:
            return "Disabling navigation..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private var navigationStatusColor: Color {
        switch navigationState {
        case .idle:
            return .secondary
        case .enabling, .disabling:
            return .orange
        case .enabled:
            return .green
        case .error:
            return .red
        }
    }
    
    private var canToggleNavigation: Bool {
        return bluetoothManager.isConnected && 
               bluetoothManager.deviceStatus?.hasGpsFix == true &&
               isDopValid &&
               bluetoothManager.deviceStatus?.targetCoordinate != nil &&
               !navigationState.isProcessing
    }
    
    private var isDopValid: Bool {
        guard let hdop = bluetoothManager.deviceStatus?.hdop else { return false }
        return hdop < 5.0
    }
    
    private func requirementRow(_ requirement: String, satisfied: Bool) -> some View {
        HStack {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(satisfied ? .green : .red)
            Text(requirement)
                .font(.caption)
            Spacer()
        }
    }
    
    private func toggleNavigation() {
        guard canToggleNavigation else {
            showNavigationError("Cannot toggle navigation - requirements not met")
            return
        }
        
        if navigationState.isEnabled {
            disableNavigation()
        } else {
            enableNavigation()
        }
    }
    
    private func enableNavigation() {
        navigationState = .enabling
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        bluetoothManager.enableNavigation()
        
        // Set timeout for response
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            if case .enabling = navigationState {
                navigationState = .error("Timeout - device did not respond")
                showNavigationError("Navigation enable timeout. Please retry.")
            }
        }
        
        // Simulate confirmation (in real implementation, this would come from device status updates)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if case .enabling = navigationState {
                navigationState = .enabled
            }
        }
    }
    
    private func disableNavigation() {
        navigationState = .disabling
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        bluetoothManager.disableNavigation()
        
        // Set timeout for response
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            if case .disabling = navigationState {
                navigationState = .error("Timeout - device did not respond")
                showNavigationError("Navigation disable timeout. Please retry.")
            }
        }
        
        // Simulate confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if case .disabling = navigationState {
                navigationState = .idle
            }
        }
    }
    
    private func syncNavigationState() {
        // Sync with device status if available
        if let status = bluetoothManager.deviceStatus,
           status.targetCoordinate != nil && status.hasGpsFix {
            navigationState = .enabled
        } else {
            navigationState = .idle
        }
    }
    
    private func handleGpsFixChange(_ hasGpsFix: Bool?) {
        guard let hasGpsFix = hasGpsFix else { return }
        
        if hasGpsFix {
            // GPS Fix restored
            if previousNavigationEnabled && navigationState == NavigationToggleState.idle {
                enableNavigation()
                showNavigationError("GPS fix restored - Navigation re-enabled")
            }
        } else {
            // GPS Fix lost - auto-disable navigation
            if navigationState.isEnabled {
                previousNavigationEnabled = true
                disableNavigation()
                showNavigationError("GPS fix lost - Navigation disabled for safety")
            }
        }
    }
    
    private func handleConnectionChange(_ isConnected: Bool) {
        if !isConnected {
            // Connection lost - reset navigation state
            if navigationState.isEnabled {
                navigationState = .error("Device disconnected")
                showNavigationError("Device disconnected - Navigation stopped")
            }
        } else {
            // Connection restored - sync state
            syncNavigationState()
        }
    }
    
    private func showNavigationError(_ message: String) {
        alertMessage = message
        showingNavigationAlert = true
        
        // Add error haptic
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
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