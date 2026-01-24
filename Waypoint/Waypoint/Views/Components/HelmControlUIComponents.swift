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
    let onJogStart: (SpotLockController.JogDirection) -> Void
    let onJogStop: () -> Void
    
    @State private var showingInitWarning = false
    
    var body: some View {
        VStack(spacing: 12) {
            if spotLockController.isDisengaging {
                disengagingIndicator
            } else {
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
                        showingInitWarning = true
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
                    .alert("Motor Initialization Required", isPresented: $showingInitWarning) {
                        Button("Cancel", role: .cancel) { }
                        Button("Continue") {
                            onEngageHere()
                        }
                    } message: {
                        Text("Before engaging Spot Lock, ensure the electric motor is:\n\n• Motor is ON\n• Speed is set to 0\n\nSpot Lock will only control speed levels.")
                    }
                }
            }
        }
    }
    
    private var disengagingIndicator: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Disengaging...")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }
            
            Text("Please wait while Spot Lock safely disengages")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var jogControls: some View {
        VStack(spacing: 8) {
            Text("Jog Position (Hold to move continuously)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                JogButton(direction: .left, icon: "arrow.left", label: "W", onPress: onJogStart, onRelease: onJogStop)
                
                VStack(spacing: 8) {
                    JogButton(direction: .forward, icon: "arrow.up", label: "N", onPress: onJogStart, onRelease: onJogStop)
                    JogButton(direction: .back, icon: "arrow.down", label: "S", onPress: onJogStart, onRelease: onJogStop)
                }
                
                JogButton(direction: .right, icon: "arrow.right", label: "E", onPress: onJogStart, onRelease: onJogStop)
            }
        }
        .padding(.vertical, 8)
        .disabled(spotLockController.isDisengaging)
    }
}

struct JogButton: View {
    let direction: SpotLockController.JogDirection
    let icon: String
    let label: String
    let onPress: (SpotLockController.JogDirection) -> Void
    let onRelease: () -> Void
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(isPressed ? .blue : .gray)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPress(direction)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
    }
}

struct ConnectionStatus: View {
    @ObservedObject var bluetooth: BluetoothManager
    
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
            
            Text("N")
                .font(.caption.bold())
                .offset(x: 0, y: -60)
            
            Text("E")
                .font(.caption.bold())
                .offset(x: 60, y: 0)
            
            Text("S")
                .font(.caption.bold())
                .offset(x: 0, y: 60)
            
            Text("W")
                .font(.caption.bold())
                .offset(x: -60, y: 0)
            
            Image(systemName: "location.north.fill")
                .font(.title)
                .foregroundColor(.red)
                .rotationEffect(.degrees(heading))
        }
    }
}