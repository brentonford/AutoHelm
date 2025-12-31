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
    let spotLockController: SpotLockController
    let canNavigate: Bool
    let onEngageHere: () -> Void
    let onEngageAtWaypoint: () -> Void
    let onDisengage: () -> Void
    let onJog: (SpotLockController.JogDirection) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status")
                Spacer()
                if spotLockController.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("Active")
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 10, height: 10)
                        Text("Inactive")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if spotLockController.isActive {
                Divider()
                
                LabeledContent("Distance from Lock") {
                    Text(String(format: "%.2f m", spotLockController.distanceFromLock))
                }
                
                LabeledContent("Speed Level") {
                    Text("\(spotLockController.currentSpeedLevel)")
                }
                
                LabeledContent("Thrust") {
                    Text(spotLockController.isApplyingThrust ? "Active" : "Inactive")
                        .foregroundColor(spotLockController.isApplyingThrust ? .green : .secondary)
                }
                
                LabeledContent("Motor State") {
                    Text(spotLockController.motorState == .on ? "On" : "Off")
                        .foregroundColor(spotLockController.motorState == .on ? .green : .secondary)
                }
                
                Divider()
                
                jogControls
                
                Divider()
                
                Button {
                    onDisengage()
                } label: {
                    HStack {
                        Image(systemName: "pin.slash.fill")
                        Text("Disengage Spot Lock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Divider()
                
                Button {
                    onEngageHere()
                } label: {
                    HStack {
                        Image(systemName: "pin.circle.fill")
                        Text("Engage at Current Position")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canNavigate)
                
            }
        }
    }
    
    private var jogControls: some View {
        VStack(spacing: 8) {
            Text("Jog Position (1.5m)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button {
                    onJog(.left)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text("W")
                            .font(.caption2)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                
                VStack(spacing: 8) {
                    Button {
                        onJog(.forward)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text("N")
                                .font(.caption2)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        onJog(.back)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text("S")
                                .font(.caption2)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    onJog(.right)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                        Text("E")
                            .font(.caption2)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
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