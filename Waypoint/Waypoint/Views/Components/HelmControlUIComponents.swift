import SwiftUI
import CoreLocation

struct ManualMotorControls: View {
    let bluetooth: BluetoothManager
    let onManualControl: () -> Void
    
    @State private var activeHoldButton: String?
    @State private var activeMomentaryButton: String?
    
    private let momentaryPressDurationMs: Int = 1000
    private let momentaryFeedbackDurationMs: Int = 300
    
    var body: some View {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private func startHoldCommand(_ command: String, label: String) {
        onManualControl()
        activeHoldButton = label
        bluetooth.sendCommand(command)
    }

    private func stopHoldCommand() {
        guard activeHoldButton != nil else { return }
        bluetooth.sendCommand("RF_RELEASE")

        Task {
            try? await Task.sleep(for: .milliseconds(momentaryFeedbackDurationMs))
            activeHoldButton = nil
        }
    }

    private func sendMomentaryCommand(_ command: String, label: String) {
        onManualControl()
        activeMomentaryButton = label
        bluetooth.sendCommand(command)

        Task {
            try? await Task.sleep(for: .milliseconds(momentaryPressDurationMs + momentaryFeedbackDurationMs))
            activeMomentaryButton = nil
        }
    }
}

struct HoldButton: View {
    let label: String
    let isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    var body: some View {
        Button(action: {}) {
            Text(label)
                .font(.title)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : .gray)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isActive {
                        onPress()
                    }
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
}

struct MomentaryButton: View {
    var label: String?
    var systemImage: String?
    let isActive: Bool
    let onPress: () -> Void
    
    var body: some View {
        Button(action: onPress) {
            Group {
                if let label = label {
                    Text(label)
                        .font(.title)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.title)
                }
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : .gray)
    }
}

struct SpotLockControls: View {
    let navigationManager: NavigationManager
    let canNavigate: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status")
                Spacer()
                Text("Coming Soon")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct WaypointInfo: View {
    let waypoint: Waypoint
    
    var body: some View {
        Group {
            LabeledContent("Waypoint") {
                Text(waypoint.name)
            }

            LabeledContent("Coordinates") {
                Text(String(format: "%.6f, %.6f",
                            waypoint.coordinate.latitude,
                            waypoint.coordinate.longitude))
                .font(.caption)
            }
        }
    }
}

struct NavigationMetrics: View {
    let waypoint: Waypoint
    let sensors: SensorData
    let targetSpeed: Double
    
    private var bearing: Double {
        sensors.currentLocation.bearing(to: waypoint.coordinate)
    }
    
    private var distance: Double {
        sensors.currentLocation.distance(to: waypoint.coordinate)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bearing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f°", bearing))
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDistance(distance))
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f km/hr", targetSpeed))
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

struct NavigationPhaseView: View {
    let phase: NavigationPhase
    
    var body: some View {
        HStack {
            Text("Navigation Phase")
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(phaseColor(phase))
                    .frame(width: 10, height: 10)
                Text(phaseText(phase))
                    .font(.subheadline.bold())
                    .foregroundColor(phaseColor(phase))
            }
        }
    }
    
    private func phaseColor(_ phase: NavigationPhase) -> Color {
        switch phase {
        case .idle: return .gray
        case .initializing, .clearingPower, .verifyingMotor: return .orange
        case .navigating, .accelerating: return .blue
        case .cruising: return .green
        case .maintaining: return .cyan
        case .spotLock: return .purple
        case .arrived, .stopping: return .green
        }
    }
    
    private func phaseText(_ phase: NavigationPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .initializing: return "Initializing"
        case .clearingPower: return "Clearing Power"
        case .verifyingMotor: return "Verifying Motor"
        case .navigating: return "Navigating"
        case .accelerating: return "Accelerating"
        case .cruising: return "Cruising"
        case .maintaining: return "Maintaining Speed"
        case .spotLock: return "Spot Lock"
        case .arrived: return "Arrived"
        case .stopping: return "Stopping"
        }
    }
}

struct CommandStatusView: View {
    let steeringCommand: String
    let speedCommand: String
    
    var body: some View {
        Group {
            HStack {
                Text("Steering Command")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(steeringCommandColor(for: steeringCommand))
                        .frame(width: 10, height: 10)
                    Text(steeringCommandDisplayText(steeringCommand))
                        .font(.subheadline.bold())
                        .foregroundColor(steeringCommandColor(for: steeringCommand))
                }
            }
            
            Divider()
            
            HStack {
                Text("Speed Command")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(speedCommandColor(for: speedCommand))
                        .frame(width: 10, height: 10)
                    Text(speedCommandDisplayText(speedCommand))
                        .font(.subheadline.bold())
                        .foregroundColor(speedCommandColor(for: speedCommand))
                }
            }
        }
    }
    
    private func steeringCommandDisplayText(_ command: String) -> String {
        switch command {
        case "LEFT": return "← LEFT"
        case "RIGHT": return "→ RIGHT"
        case "On Course": return "✓ On Course"
        case "None": return "⊗ None"
        default: return command
        }
    }

    private func steeringCommandColor(for command: String) -> Color {
        switch command {
        case "LEFT", "RIGHT": return .orange
        case "On Course": return .green
        default: return .gray
        }
    }
    
    private func speedCommandDisplayText(_ command: String) -> String {
        switch command {
        case "SPEED+": return "↑ SPEED +"
        case "SPEED-": return "↓ SPEED -"
        case "At Target": return "✓ At Target"
        case "Stopped": return "⊗ Stopped"
        default: return command
        }
    }
    
    private func speedCommandColor(for command: String) -> Color {
        switch command {
        case "SPEED+": return .blue
        case "SPEED-": return .orange
        case "At Target": return .green
        default: return .gray
        }
    }
}

struct SpeedStatusView: View {
    let gpsSpeed: Double
    let powerLevel: Int
    
    var body: some View {
        Group {
            if gpsSpeed > 0 {
                LabeledContent("GPS Speed", value: String(format: "%.1f km/hr", gpsSpeed))
            }
            if powerLevel > 0 {
                let estimatedSpeed = Double(powerLevel) * 0.36
                LabeledContent("Est. Speed", value: String(format: "%.1f km/hr", estimatedSpeed))
            }
        }
    }
}

struct ConnectionStatus: View {
    let bluetooth: BluetoothManager
    
    var body: some View {
        HStack {
            Circle()
                .fill(bluetooth.connectionState == .connected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
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

struct GpsStatusView: View {
    let sensors: SensorData
    
    var body: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signal Quality")
                        .font(.subheadline)
                    Text(sensors.gpsQuality.label)
                        .font(.title3.bold())
                        .foregroundColor(Color(sensors.gpsQuality.color))
                }
                
                Spacer()
                
                Image(systemName: sensors.gpsQuality.icon)
                    .font(.largeTitle)
                    .foregroundColor(Color(sensors.gpsQuality.color))
            }
            .padding(.vertical, 8)
            
            LabeledContent("Satellites", value: "\(sensors.satellites)")
            LabeledContent("Accuracy (HDOP)", value: String(format: "%.1f", sensors.hdop))
            
            if sensors.hasFix {
                LabeledContent("Position") {
                    Text(String(format: "%.6f, %.6f", sensors.currentLat, sensors.currentLon))
                        .font(.caption)
                }
            }
        }
    }
}

struct CompassStatusView: View {
    let sensors: SensorData
    
    var body: some View {
        Group {
            HStack {
                Spacer()
                CompassView(heading: sensors.heading, bearing: nil)
                    .frame(width: 150, height: 150)
                Spacer()
            }
            .listRowBackground(Color.clear)
            
            LabeledContent("Heading", value: String(format: "%.1f°", sensors.heading))
        }
    }
}

struct CompassView: View {
    let heading: Double
    let bearing: Double?
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            ForEach(["N", "E", "S", "W"], id: \.self) { direction in
                Text(direction)
                    .font(.caption.bold())
                    .offset(y: directionOffset(for: direction))
            }
            
            Image(systemName: "location.north.fill")
                .font(.title)
                .foregroundColor(.red)
                .rotationEffect(.degrees(-heading))
        }
    }
    
    private func directionOffset(for direction: String) -> CGFloat {
        switch direction {
        case "N": return -60
        case "E": return 0
        case "S": return 60
        case "W": return 0
        default: return 0
        }
    }
}