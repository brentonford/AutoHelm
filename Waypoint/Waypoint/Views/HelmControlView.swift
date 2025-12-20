import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    let selectedWaypoint: Waypoint?
    @Binding var navigationEnabled: Bool
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var activeHoldButton: String?
    @State private var activeMomentaryButton: String?
    @State private var commandFeedback: String?
    
    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }
    
    private var navigationFunctioning: Bool {
        navigationEnabled && !navigationBlocked
    }
    
    var body: some View {
        List {
            connectionSection
            gpsStatusSection
            compassSection
            navigationControlSection
            motorControlSection
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
                activeHoldButton = nil
                activeMomentaryButton = nil
                commandFeedback = nil
            }
        }
        .onChange(of: bluetooth.lastResponse) { _, response in
            isLoading = false
            if response != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    commandFeedback = nil
                }
            }
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
        Section {
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
                }
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        } header: {
            HStack {
                Text("GPS Status")
                Spacer()
                Circle()
                    .fill(gpsStatusColor)
                    .frame(width: 10, height: 10)
            }
        }
    }
    
    private var gpsStatusColor: Color {
        guard let status = bluetooth.deviceStatus else { return .red }
        if !status.hasFix { return .red }
        if status.hdop >= 5.0 { return .orange }
        return .green
    }
    
    // MARK: - Compass Section
    
    private var compassSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                HStack {
                    Spacer()
                    CompassView(heading: status.heading, bearing: status.hasTarget == true ? status.bearing : nil)
                        .frame(width: 150, height: 150)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                
                LabeledContent("Heading", value: String(format: "%.1f°", status.heading))
                
                if status.hasTarget == true {
                    LabeledContent("Bearing to Target", value: String(format: "%.1f°", status.bearing))
                }
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        } header: {
            HStack {
                Text("Compass")
                Spacer()
                Circle()
                    .fill(bluetooth.deviceStatus != nil ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }
        }
    }
    
    // MARK: - Navigation Control Section
    
    private var navigationControlSection: some View {
        Section {
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
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Navigation Enabled", isOn: $navigationEnabled)
                    .onChange(of: navigationEnabled) { _, enabled in
                        toggleNavigation(enabled)
                    }
                
                if navigationBlocked {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(blockReason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if navigationFunctioning {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Navigation Active - Autonomous Control")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        } header: {
            Text("Autonomous Navigation")
        } footer: {
            Text(navigationFunctioning ? "Helm is autonomously navigating to waypoint" : "Enable navigation when GPS is ready and Helm is connected")
                .font(.caption)
        }
    }
    
    private var blockReason: String {
        guard bluetooth.connectionState == .connected else {
            return "Navigation blocked: Helm not connected"
        }
        guard let status = bluetooth.deviceStatus else {
            return "Navigation blocked: No GPS data"
        }
        if !status.hasFix {
            return "Navigation blocked: No GPS fix"
        }
        if status.satellites < 4 {
            return "Navigation blocked: Insufficient satellites (\(status.satellites)/4)"
        }
        if status.hdop >= 5.0 {
            return "Navigation blocked: Poor GPS accuracy (HDOP: \(String(format: "%.1f", status.hdop)))"
        }
        return "Navigation blocked"
    }
    
    private func correctionDirection(_ relative: Double) -> String {
        if abs(relative) <= 15.0 {
            return "✓ On course"
        }
        return relative > 0 ? "→ Turn RIGHT" : "← Turn LEFT"
    }
    
    // MARK: - Motor Control Section
    
    private var motorControlSection: some View {
        Section {
            VStack(spacing: 16) {
                // Top row: Left (hold), Speed+ (momentary), Right (hold)
                HStack(spacing: 20) {
                    HoldButton(label: "◀", isActive: activeHoldButton == "LEFT") {
                        startHoldCommand("RF_LEFT_HOLD", label: "LEFT")
                    } onRelease: {
                        stopHoldCommand()
                    }
                    
                    MomentaryButton(label: "+", isActive: activeMomentaryButton == "UP") {
                        sendMomentaryCommand("RF_UP", label: "SPEED+")
                    }
                    
                    HoldButton(label: "▶", isActive: activeHoldButton == "RIGHT") {
                        startHoldCommand("RF_RIGHT_HOLD", label: "RIGHT")
                    } onRelease: {
                        stopHoldCommand()
                    }
                }
                
                // Bottom row: Momentary (M), Speed- (momentary), Motor (momentary)
                HStack(spacing: 20) {
                    MomentaryButton(label: "M", isActive: activeMomentaryButton == "MOMENTARY") {
                        sendMomentaryCommand("RF_MOMENTARY", label: "MOMENTARY")
                    }
                    
                    MomentaryButton(label: "-", isActive: activeMomentaryButton == "DOWN") {
                        sendMomentaryCommand("RF_DOWN", label: "SPEED-")
                    }
                    
                    MomentaryButton(systemImage: "fanblades", isActive: activeMomentaryButton == "MOTOR") {
                        sendMomentaryCommand("RF_MOTOR", label: "MOTOR")
                    }
                }
                
                if let feedback = commandFeedback {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(feedback)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Manual Motor Control")
        } footer: {
            Text("Left/Right: Hold to steer • Others: Tap for 1 second pulse")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func startHoldCommand(_ command: String, label: String) {
        activeHoldButton = label
        commandFeedback = "Sending \(label)..."
        bluetooth.sendCommand(command)
    }
    
    private func stopHoldCommand() {
        if activeHoldButton != nil {
            commandFeedback = "Releasing..."
            bluetooth.sendCommand("RF_RELEASE")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                activeHoldButton = nil
                commandFeedback = nil
            }
        }
    }
    
    private func sendMomentaryCommand(_ command: String, label: String) {
        activeMomentaryButton = label
        commandFeedback = "Sending \(label) (1s)..."
        bluetooth.sendCommand(command)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            activeMomentaryButton = nil
            commandFeedback = nil
        }
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
                        Text("Send to Helm & Enable Navigation")
                    }
                }
                .disabled(bluetooth.connectionState != .connected || isLoading)
            } else {
                Text("No waypoint selected")
                    .foregroundColor(.secondary)
                Text("Tap on the map or select from waypoint list")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleNavigation(_ enabled: Bool) {
        isLoading = true
        commandFeedback = enabled ? "Enabling navigation..." : "Disabling navigation..."
        
        if enabled {
            bluetooth.enableNavigation()
        } else {
            bluetooth.disableNavigation()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            commandFeedback = nil
        }
    }
    
    private func sendWaypoint(_ waypoint: Waypoint) {
        isLoading = true
        commandFeedback = "Sending waypoint..."
        bluetooth.sendWaypoint(waypoint)
        
        // Auto-enable navigation after sending waypoint
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            navigationEnabled = true
            bluetooth.enableNavigation()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            commandFeedback = nil
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Compass View

struct CompassView: View {
    let heading: Double
    let bearing: Double?
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            ForEach(cardinalDirections, id: \.0) { direction, angle in
                Text(direction)
                    .font(.caption.bold())
                    .foregroundColor(direction == "N" ? .red : .primary)
                    .rotationEffect(.degrees(-heading))
                    .offset(y: -55)
                    .rotationEffect(.degrees(angle))
            }
            
            ForEach(0..<36, id: \.self) { i in
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 10 : 5)
                    .offset(y: -65)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
            
            if let bearing = bearing {
                BearingIndicator()
                    .rotationEffect(.degrees(bearing - heading))
            }
            
            HeadingIndicator()
        }
        .rotationEffect(.degrees(heading))
    }
    
    private var cardinalDirections: [(String, Double)] {
        [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
    }
}

struct HeadingIndicator: View {
    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.red)
                .frame(width: 16, height: 20)
            Rectangle()
                .fill(Color.red)
                .frame(width: 4, height: 35)
        }
        .offset(y: -25)
    }
}

struct BearingIndicator: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 12, height: 12)
            .offset(y: -45)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Hold Button (for Left/Right)

struct HoldButton: View {
    var label: String?
    var systemImage: String?
    var isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            
            if let label = label {
                Text(label)
                    .font(.title2.bold())
                    .foregroundColor(isActive ? .blue : .primary)
            } else if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(isActive ? .blue : .primary)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isActive {
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isActive {
                        onRelease()
                    }
                }
        )
    }
}

// MARK: - Momentary Button (for Speed+/-, M, Motor)

struct MomentaryButton: View {
    var label: String?
    var systemImage: String?
    var isActive: Bool
    let onPress: () -> Void
    
    var body: some View {
        Button(action: onPress) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                if let label = label {
                    Text(label)
                        .font(.title2.bold())
                        .foregroundColor(isActive ? .blue : .primary)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(isActive ? .blue : .primary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}