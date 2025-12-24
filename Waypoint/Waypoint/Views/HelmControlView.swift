import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    
    @Binding var waypoints: [Waypoint]
    @Binding var selectedWaypoint: Waypoint?
    @Binding var navigationEnabled: Bool
    
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var activeHoldButton: String?
    @State private var activeMomentaryButton: String?
    @State private var commandFeedback: String?
    @State private var targetSpeedText = "3.6"
    @FocusState private var speedFieldFocused: Bool
    @State private var showingArrivalAlert = false
    @State private var totalDistance: Double = 0
    @State private var showingWaypointList = false
    
    private enum Constants {
        static let feedbackDelaySeconds: Double = 0.3
        static let momentaryButtonDurationSeconds: Double = 0.8
        static let holdReleaseDelaySeconds: Double = 0.3
        static let waypointSendDelaySeconds: Double = 0.5
        static let minSpeed: Double = 0
        static let maxSpeed: Double = 10
        static let defaultAverageSpeedMs: Double = 1.0
    }

    // MARK: - Computed Properties

    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }

    private var navigationFunctioning: Bool {
        navigationEnabled && !navigationBlocked
    }
    
    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let status = bluetooth.deviceStatus else { return false }
        return status.hasFix && status.isNavigationReady
    }
    
    private var isActiveNavigation: Bool {
        guard let status = bluetooth.deviceStatus else { return false }
        return navigationEnabled && status.hasTarget == true
    }
    
    private var navigationProgress: Double {
        guard let status = bluetooth.deviceStatus,
              status.hasTarget == true,
              totalDistance > 0 else { return 0 }
        
        let remaining = status.distance
        let traveled = totalDistance - remaining
        return min(max(traveled / totalDistance, 0), 1.0)
    }

    // MARK: - Body

    var body: some View {
        List {
            motorControlSection
            spotLockSection
            autonomousNavigationSection
            autonomousCommandSection
            connectionSection
            gpsStatusSection
            compassSection
        }
        .toolbar {
            StatusToolbar {
                showingWaypointList = true
            }
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(
                waypoints: $waypoints,
                selectedWaypoint: $selectedWaypoint,
                navigationEnabled: $navigationEnabled
            )
        }
        .alert("Arrived!", isPresented: $showingArrivalAlert) {
            Button("OK") {
                showingArrivalAlert = false
            }
        } message: {
            if let waypoint = selectedWaypoint {
                Text("You have arrived at \(waypoint.name)")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: bluetooth.lastError) { _, error in
            handleError(error)
        }
        .onChange(of: bluetooth.lastResponse) { _, response in
            handleResponse(response)
        }
        .onChange(of: bluetooth.deviceStatus?.distance) { oldValue, newValue in
            checkArrival(oldDistance: oldValue, newDistance: newValue)
        }
        .onChange(of: navigationEnabled) { _, enabled in
            handleNavigationToggle(enabled)
        }
        .onChange(of: selectedWaypoint?.id) { _, _ in
            handleWaypointChange()
        }
        .onChange(of: bluetooth.connectionState) { _, newState in
            if newState != .connected && navigationEnabled {
                navigationEnabled = false
            }
            if newState != .connected {
                totalDistance = 0
            }
        }
        .onChange(of: bluetooth.deviceStatus?.hasTarget) { _, hasTarget in
            if hasTarget == true, navigationEnabled, let status = bluetooth.deviceStatus {
                if totalDistance == 0 {
                    totalDistance = status.distance
                }
            }
        }
    }

    private var connectionSection: some View {
        Section("Helm Device") {
            HStack {
                connectionIndicator
                Text(bluetooth.connectionState.rawValue)
                Spacer()
                
                SignalStrengthIndicator(
                    label: "BLE:",
                    signalStrength: bluetooth.signalStrength
                )
                
                if bluetooth.connectionState == .disconnected {
                    Button("Connect") {
                        bluetooth.startScanning()
                    }
                }
            }
            
            if let status = bluetooth.deviceStatus {
                HStack {
                    Text("Motor Response")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.isMotorResponding ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(status.isMotorResponding ? "Responding" : "No Response")
                            .font(.subheadline)
                            .foregroundColor(status.isMotorResponding ? .green : .red)
                    }
                }
            }
        }
    }
    
    private var connectionIndicator: some View {
        Circle()
            .fill(bluetooth.connectionState == .connected ? Color.green : Color.red)
            .frame(width: 12, height: 12)
    }
    
    // MARK: - Event Handlers
    
    private func handleError(_ error: String?) {
        guard let error else { return }
        errorMessage = error
        showingError = true
        isLoading = false
        activeHoldButton = nil
        activeMomentaryButton = nil
        commandFeedback = nil
    }
    
    private func handleResponse(_ response: BleResponse?) {
        isLoading = false
        guard response != nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            commandFeedback = nil
        }
    }
    
    private func handleNavigationToggle(_ enabled: Bool) {
        guard enabled, let status = bluetooth.deviceStatus, status.hasTarget == true else { return }
        totalDistance = status.distance
    }
    
    private func handleWaypointChange() {
        guard let status = bluetooth.deviceStatus else { return }
        
        if navigationEnabled && status.hasTarget == true {
            totalDistance = status.distance
        } else if selectedWaypoint != nil {
            let helmLocation = status.currentLocation
            if let waypoint = selectedWaypoint {
                totalDistance = helmLocation.distance(to: waypoint.coordinate)
            }
        }
    }
    
    private func checkArrival(oldDistance: Double?, newDistance: Double?) {
        guard let newDistance,
              let waypoint = selectedWaypoint,
              navigationEnabled else { return }
        
        let arrivalThreshold = waypoint.arrivalRadius
        
        guard newDistance <= arrivalThreshold else { return }
        
        showingArrivalAlert = true
        navigationEnabled = false
        bluetooth.disableNavigation()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Spot Lock Section
    
    private var spotLockSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                HStack {
                    Text(status.isSpotLockActive ? "ACTIVE" : "OFF")
                        .foregroundColor(status.isSpotLockActive ? Color.green : .secondary)
                    Spacer()
                    Button(status.isSpotLockActive ? "Disengage" : "Engage") {
                        toggleSpotLock(isActive: status.isSpotLockActive)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.isSpotLockActive ? Color.red : Color.blue)
                }

                if status.isSpotLockActive {
                    LabeledContent("Distance from Lock", value: formatDistance(status.distance))
                }

                if status.isSpotLockActive {
                    spotLockJogControls
                }
            }
        } header: {
            Text("Spot Lock")
        } footer: {
            Text("Spot Lock holds position at the current GPS location.\nJog moves the lock point ~1.5m.\nEngaging spot lock disables autonomous navigation")
        }
    }
    
    private func toggleSpotLock(isActive: Bool) {
        if isActive {
            bluetooth.disengageSpotLock()
        } else {
            if navigationEnabled {
                navigationEnabled = false
                bluetooth.disableNavigation()
            }
            bluetooth.engageSpotLock()
        }
    }
    
    private var spotLockJogControls: some View {
        VStack(spacing: 8) {
            Text("Jog Position")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Spacer()
                Button(action: { bluetooth.jogSpotLock(direction: .forward) }) {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            HStack(spacing: 16) {
                Button(action: { bluetooth.jogSpotLock(direction: .left) }) {
                    Image(systemName: "arrow.left")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { bluetooth.jogSpotLock(direction: .back) }) {
                    Image(systemName: "arrow.down")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { bluetooth.jogSpotLock(direction: .right) }) {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Motor Control Section

    private var motorControlSection: some View {
        Section {
            VStack(spacing: 16) {
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
            Text("Remote Control")
        } footer: {
            Text("Left/Right: Hold to steer • Others: Tap for 1 second pulse\nUsing remote control disables autonomous navigation")
        }
    }

    private func startHoldCommand(_ command: String, label: String) {
        if navigationEnabled {
            navigationEnabled = false
            bluetooth.disableNavigation()
        }
        
        activeHoldButton = label
        commandFeedback = "Sending \(label)..."
        bluetooth.sendCommand(command)
    }

    private func stopHoldCommand() {
        guard activeHoldButton != nil else { return }
        
        commandFeedback = "Releasing..."
        bluetooth.sendCommand("RF_RELEASE")

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            activeHoldButton = nil
            commandFeedback = nil
        }
    }

    private func sendMomentaryCommand(_ command: String, label: String) {
        if navigationEnabled {
            navigationEnabled = false
            bluetooth.disableNavigation()
        }
        
        activeMomentaryButton = label
        commandFeedback = "Sending \(label) (1s)..."
        bluetooth.sendCommand(command)

        Task {
            try? await Task.sleep(for: .milliseconds(800))
            activeMomentaryButton = nil
            commandFeedback = nil
        }
    }

    // MARK: - Autonomous Navigation Section

    private var autonomousNavigationSection: some View {
        Section {
            if let waypoint = selectedWaypoint, let status = bluetooth.deviceStatus, status.hasTarget == true {
                LabeledContent("Waypoint") {
                    Text(waypoint.name)
                }

                LabeledContent("Coordinates") {
                    Text(String(format: "%.6f, %.6f",
                                waypoint.coordinate.latitude,
                                waypoint.coordinate.longitude))
                    .font(.caption)
                }
                HStack {
                    Text(String(status.navState?.capitalized ?? "Unknown"))
                        .foregroundColor(.secondary)

                    Spacer()

                    if navigationEnabled {
                        Button {
                            navigationEnabled = false
                            bluetooth.disableNavigation()
                        } label: {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop Navigation")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.red)
                        .disabled(bluetooth.connectionState != .connected)
                    } else {
                        Button {
                            sendWaypointAndEnableNavigation(waypoint)
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Image(systemName: "location.fill")
                                Text("Navigate to Waypoint")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canNavigate || isLoading)
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bearing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f deg", status.bearing))
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDistance(status.distance))
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("Est. Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let eta = status.distance / Constants.defaultAverageSpeedMs
                        Text(formatEstimatedTime(eta))
                            .font(.headline)
                    }
                }
            } else {
                Text("No waypoint selected")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Autonomous Navigation")
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

    // MARK: - Autonomous Command Section

    private var autonomousCommandSection: some View {
        Section {
            if let status = bluetooth.deviceStatus, navigationEnabled {
                VStack(spacing: 12) {
                    // Steering Command - from device
                    steeringCommandRow(status: status)
                    
                    if let relative = status.relative {
                        LabeledContent("Correction Angle", value: String(format: "%+.1f deg", relative))
                    }
                    
                    Divider()
                    
                    // Speed Command - from device
                    speedCommandRow(status: status)
                    
                    // Acceleration/Deceleration State
                    if status.isAccelerating == true {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                            Text("Gradually Accelerating...")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    } else if status.isDecelerating == true {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.orange)
                            Text("Decelerating...")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    
                    LabeledContent("Power Level", value: "\(status.speedLevel ?? 0)/10")
                    if let speedKmh = status.speedKmh {
                        LabeledContent("Est. Speed", value: String(format: "%.1f km/hr", speedKmh))
                    }

                    HStack {
                        TextField("Speed (km/hr)", text: $targetSpeedText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($speedFieldFocused)
                        
                        Button("Set") {
                            setTargetSpeed()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    // Emergency Stop Button
                    Button {
                        sendEmergencyStop()
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                            Text("Emergency Stop")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Steering: Every 2s when correction needed.\nSpeed: Gradual acceleration (1.5s between steps).\nRange: 0.0-10.0 km/hr")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Navigation disabled")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Autonomous Commands")
        } footer: {
            Text("Commands sent to motor are shown above. Motor response is detected via GPS/compass changes.")
        }
    }
    
    private func steeringCommandRow(status: DeviceStatus) -> some View {
        HStack {
            Text("Steering Command")
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(steeringCommandColor(for: status.steeringCommand))
                    .frame(width: 10, height: 10)
                Text(steeringCommandDisplayText(status.steeringCommand))
                    .font(.subheadline.bold())
                    .foregroundColor(steeringCommandColor(for: status.steeringCommand))
            }
        }
    }
    
    private func speedCommandRow(status: DeviceStatus) -> some View {
        HStack {
            Text("Speed Command")
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(speedCommandColor(for: status.speedCommand))
                    .frame(width: 10, height: 10)
                Text(speedCommandDisplayText(status.speedCommand))
                    .font(.subheadline.bold())
                    .foregroundColor(speedCommandColor(for: status.speedCommand))
            }
        }
    }

    private func steeringCommandDisplayText(_ command: String) -> String {
        switch command {
        case "LEFT": return "← LEFT"
        case "RIGHT": return "→ RIGHT"
        case "On Course": return "✓ On Course"
        case "STOP": return "⊗ STOPPED"
        default: return command
        }
    }

    private func steeringCommandColor(for command: String) -> Color {
        switch command {
        case "LEFT", "RIGHT": return .orange
        case "On Course": return .green
        case "STOP": return .red
        default: return .gray
        }
    }
    
    private func speedCommandDisplayText(_ command: String) -> String {
        switch command {
        case "SPEED+": return "↑ SPEED +"
        case "SPEED-": return "↓ SPEED -"
        case "At Target": return "✓ At Target"
        case "Stopped": return "⊗ Stopped"
        case "STOP": return "⊗ STOPPED"
        default: return command
        }
    }
    
    private func speedCommandColor(for command: String) -> Color {
        switch command {
        case "SPEED+": return .blue
        case "SPEED-": return .orange
        case "At Target": return .green
        case "Stopped", "STOP": return .red
        default: return .gray
        }
    }
    
    private func setTargetSpeed() {
        guard let speed = Double(targetSpeedText),
              speed >= Constants.minSpeed && speed <= Constants.maxSpeed else {
            errorMessage = "Speed must be between \(Int(Constants.minSpeed)) and \(Int(Constants.maxSpeed)) km/hr"
            showingError = true
            return
        }
        bluetooth.setSpeed(speed)
        speedFieldFocused = false
    }
    
    private func sendEmergencyStop() {
        bluetooth.sendCommand("EMERGENCY_STOP")
        navigationEnabled = false
    }

    // MARK: - GPS Status Section

    private var gpsStatusSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signal Quality")
                            .font(.subheadline)
                        Text(status.gpsQuality.label)
                            .font(.title3.bold())
                            .foregroundColor(Color(status.gpsQuality.color))
                    }
                    
                    Spacer()
                    
                    Image(systemName: status.gpsQuality.icon)
                        .font(.largeTitle)
                        .foregroundColor(Color(status.gpsQuality.color))
                }
                .padding(.vertical, 8)

                LabeledContent("Satellites", value: "\(status.satellites)")
                LabeledContent("Accuracy (HDOP)", value: String(format: "%.1f", status.hdop))

                if status.hasFix {
                    LabeledContent("Position") {
                        Text(String(format: "%.6f, %.6f", status.currentLat, status.currentLon))
                            .font(.caption)
                    }
                }
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("GPS Status")
        }
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

                LabeledContent("Heading", value: String(format: "%.1f deg", status.heading))

                if status.hasTarget == true {
                    LabeledContent("Bearing to Target", value: String(format: "%.1f deg", status.bearing))
                }
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Compass")
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

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            commandFeedback = nil
        }
    }

    private func sendWaypointAndEnableNavigation(_ waypoint: Waypoint) {
        guard let status = bluetooth.deviceStatus else { return }
        
        let helmLocation = status.currentLocation
        isLoading = true
        commandFeedback = "Sending waypoint..."
        totalDistance = helmLocation.distance(to: waypoint.coordinate)
        bluetooth.sendWaypoint(waypoint)

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            navigationEnabled = true
            bluetooth.enableNavigation()
        }

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            commandFeedback = nil
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
    
    private func formatEstimatedTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - Compass View

struct CompassView: View {
    let heading: Double
    let bearing: Double?

    private let cardinalDirections: [(String, Double)] = [
        ("N", 0), ("E", 90), ("S", 180), ("W", 270)
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)

            ForEach(cardinalDirections, id: \.0) { direction, angle in
                Text(direction)
                    .font(.caption.bold())
                    .foregroundColor(direction == "N" ? Color.red : .primary)
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

            if let bearing {
                BearingIndicator()
                    .rotationEffect(.degrees(bearing - heading))
            }

            HeadingIndicator()
        }
        .rotationEffect(.degrees(heading))
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
    nonisolated func path(in rect: CGRect) -> SwiftUI.Path {
        var path = SwiftUI.Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Hold Button

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

            if let label {
                Text(label)
                    .font(.title2.bold())
                    .foregroundColor(isActive ? Color.blue : .primary)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(isActive ? Color.blue : .primary)
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
        .accessibilityLabel(label ?? systemImage ?? "Button")
    }
}

// MARK: - Momentary Button

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

                if let label {
                    Text(label)
                        .font(.title2.bold())
                        .foregroundColor(isActive ? Color.blue : .primary)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(isActive ? Color.blue : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? systemImage ?? "Button")
    }
}