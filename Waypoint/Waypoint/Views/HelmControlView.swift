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
    @State private var targetSpeedText = "3.6"
    @FocusState private var speedFieldFocused: Bool
    @State private var showingArrivalAlert = false
    @State private var lastDistance: Double = 0
    @State private var totalDistance: Double = 0

    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }

    private var navigationFunctioning: Bool {
        navigationEnabled && !navigationBlocked
    }
    
    private var navigationProgress: Double {
        guard let status = bluetooth.deviceStatus,
              status.hasTarget == true,
              totalDistance > 0 else { return 0 }
        
        let remaining = status.distance
        let traveled = totalDistance - remaining
        return min(max(traveled / totalDistance, 0), 1.0)
    }

    var body: some View {
        List {
            connectionSection
            spotLockSection
            motorControlSection
            navigationControlSection
            waypointSection
            navigationProgressSection
            speedControlSection
            gpsStatusSection
            compassSection
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
        .onChange(of: bluetooth.deviceStatus?.distance) { oldValue, newValue in
            checkArrival(oldDistance: oldValue, newDistance: newValue)
        }
        .onChange(of: navigationEnabled) { _, enabled in
            if enabled, let status = bluetooth.deviceStatus, status.hasTarget == true {
                totalDistance = status.distance
            }
        }
    }

    // MARK: - Connection Section

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
        }
    }
    
    // MARK: - Arrival Detection
    
    private func checkArrival(oldDistance: Double?, newDistance: Double?) {
        guard let newDistance = newDistance,
              let waypoint = selectedWaypoint,
              navigationEnabled else { return }
        
        let arrivalThreshold = waypoint.arrivalRadius
        
        if newDistance <= arrivalThreshold {
            showingArrivalAlert = true
            navigationEnabled = false
            bluetooth.disableNavigation()
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Navigation Progress Section
    
    private var navigationProgressSection: some View {
        Group {
            if let status = bluetooth.deviceStatus, status.hasTarget == true, navigationEnabled {
                Section("Navigation Progress") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Progress")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(navigationProgress * 100))%")
                                .font(.subheadline.bold())
                        }
                        
                        ProgressView(value: navigationProgress, total: 1.0)
                            .tint(Color.blue)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Distance")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDistance(status.distance))
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Total")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDistance(totalDistance))
                                    .font(.headline)
                            }
                        }
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
                .disabled(bluetooth.connectionState != .connected || isLoading)
            } else {
                Text("No waypoint selected")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Navigation Control Section

    private var navigationControlSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                LabeledContent("State", value: status.navState?.capitalized ?? "Unknown")

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
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Navigation")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $navigationEnabled)
                        .labelsHidden()
                        .onChange(of: navigationEnabled) { _, enabled in
                            toggleNavigation(enabled)
                        }
                    Text(navigationEnabled ? "ON" : "OFF")
                        .font(.subheadline.bold())
                        .foregroundColor(navigationEnabled ? Color.green : .secondary)
                }

                if navigationBlocked && navigationEnabled {
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
                            .foregroundColor(Color.green)
                            .font(.caption)
                        Text("Navigation Active")
                            .font(.caption)
                            .foregroundColor(Color.green)
                    }
                }
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
        // Disable navigation when manual control used
        if navigationEnabled {
            navigationEnabled = false
            bluetooth.disableNavigation()
        }
        
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
        // Disable navigation when manual control used
        if navigationEnabled {
            navigationEnabled = false
            bluetooth.disableNavigation()
        }
        
        activeMomentaryButton = label
        commandFeedback = "Sending \(label) (1s)..."
        bluetooth.sendCommand(command)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            activeMomentaryButton = nil
            commandFeedback = nil
        }
    }

    // MARK: - Spot Lock Section

    private var spotLockSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                HStack {
                    Text("Spot Lock")
                    Spacer()
                    Text(status.isSpotLockActive ? "ACTIVE" : "OFF")
                        .foregroundColor(status.isSpotLockActive ? Color.green : .secondary)
                }

                if status.isSpotLockActive {
                    LabeledContent("Distance from Lock", value: formatDistance(status.distance))
                }

                HStack(spacing: 16) {
                    Button(status.isSpotLockActive ? "Disengage" : "Engage") {
                        if status.isSpotLockActive {
                            bluetooth.disengageSpotLock()
                        } else {
                            // Disable navigation when spot lock engaged
                            if navigationEnabled {
                                navigationEnabled = false
                                bluetooth.disableNavigation()
                            }
                            bluetooth.engageSpotLock()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.isSpotLockActive ? Color.red : Color.blue)
                }

                if status.isSpotLockActive {
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
            }
        } header: {
            Text("Spot Lock (Station Keeping)")
        } footer: {
            Text("Spot Lock holds position at the current GPS location. Jog moves the lock point ~5 feet.\nEngaging spot lock disables autonomous navigation")
        }
    }

    // MARK: - Speed Control Section

    private var speedControlSection: some View {
        Section {
            if let status = bluetooth.deviceStatus {
                LabeledContent("Current Level", value: "\(status.speedLevel ?? 0)/10")
                LabeledContent("Target Level", value: "\(status.targetSpeed ?? 0)/10")

                if let speedKmh = status.speedKmh {
                    LabeledContent("Est. Speed", value: String(format: "%.1f km/hr", speedKmh))
                }
            }

            HStack {
                TextField("Speed (km/hr)", text: $targetSpeedText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($speedFieldFocused)
                
                Button("Set") {
                    if let speed = Double(targetSpeedText), speed >= 0 && speed <= 10 {
                        bluetooth.setSpeed(speed)
                        speedFieldFocused = false
                    } else {
                        errorMessage = "Speed must be between 0 and 10 km/hr"
                        showingError = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Speed Control")
        } footer: {
            Text("Default cruise speed is 3.6 km/hr (1 m/s). Enter a value between 0-10 km/hr")
        }
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

                LabeledContent("Heading", value: String(format: "%.1f°", status.heading))

                if status.hasTarget == true {
                    LabeledContent("Bearing to Target", value: String(format: "%.1f°", status.bearing))
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            commandFeedback = nil
        }
    }

    private func sendWaypointAndEnableNavigation(_ waypoint: Waypoint) {
        isLoading = true
        commandFeedback = "Sending waypoint..."
        bluetooth.sendWaypoint(waypoint)

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

// MARK: - Compass View (unchanged)

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
    nonisolated func path(in rect: CGRect) -> SwiftUI.Path {
        var path = SwiftUI.Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Hold Button (unchanged)

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
                    .foregroundColor(isActive ? Color.blue : .primary)
            } else if let systemImage = systemImage {
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
    }
}

// MARK: - Momentary Button (unchanged)

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
                        .foregroundColor(isActive ? Color.blue : .primary)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(isActive ? Color.blue : .primary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
