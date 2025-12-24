import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    
    @Binding var waypoints: [Waypoint]
    @Binding var selectedWaypoint: Waypoint?
    @Binding var navigationEnabled: Bool
    
    @State var showingError = false
    @State var errorMessage = ""
    @State var activeHoldButton: String?
    @State var activeMomentaryButton: String?
    @State var commandFeedback: String?
    @State var showingArrivalAlert = false
    @State var totalDistance: Double = 0
    @State var showingWaypointList = false
    
    @State var navigationTimer: Timer?
    @State var motorOn = false
    @State var currentSpeedLevel: Int = 0
    @State var targetSpeedLevel: Int = 10
    @State var targetSpeedKmh: Double = 3.6
    @State var lastSpeedCommandTime: Date?
    @State var accelerationStartTime: Date?
    @State var steeringCommand: String = "None"
    @State var speedCommand: String = "Stopped"
    @State var navigationPhase: NavigationPhase = .idle
    @State var motorVerificationAttempts: Int = 0
    @State var lastGpsSpeed: Double = 0
    @State var speedVerificationStartTime: Date?
    
    @State var spotLockTimer: Timer?
    @State var spotLockPosition: CLLocationCoordinate2D?
    @State var isSpotLockEngaged = false
    @State var isHoldingMomentary = false
    
    enum NavigationPhase {
        case idle
        case clearingPowerLevel
        case verifyingMotor
        case accelerating
        case cruising
        case maintaining
        case spotLock
        case arrived
    }
    
    enum Constants {
        static let navigationCommandDelaySeconds: Double = 2.0
        static let speedMaintenanceIntervalSeconds: Double = 5.0
        static let motorVerificationDelaySeconds: Double = 3.0
        static let spotLockHoldRadius: Double = 2.0
        static let headingToleranceDegrees: Double = 15.0
        static let jogDistanceM: Double = 1.5
        static let speedToleranceKmh: Double = 0.5
        static let maxMotorVerificationAttempts: Int = 3
    }

    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return sensors.hasFix && sensors.isNavigationReady
    }

    var body: some View {
        listContent
            .applyHelmControlToolbar(showingWaypointList: $showingWaypointList)
            .applyHelmControlSheets(
                showingWaypointList: $showingWaypointList,
                waypoints: $waypoints,
                selectedWaypoint: $selectedWaypoint,
                navigationEnabled: $navigationEnabled
            )
            .applyHelmControlAlerts(
                showingArrivalAlert: $showingArrivalAlert,
                showingError: $showingError,
                errorMessage: errorMessage,
                selectedWaypoint: selectedWaypoint
            )
            .applyHelmControlChangeHandlers(
                navigationEnabled: $navigationEnabled,
                selectedWaypoint: selectedWaypoint,
                bluetooth: bluetooth,
                showingError: $showingError,
                errorMessage: $errorMessage,
                onNavigationToggle: handleNavigationToggle,
                onWaypointChange: handleWaypointChange,
                onConnectionChange: {
                    stopAllAutomation()
                },
                onSensorDataUpdate: {
                    if let sensors = bluetooth.sensorData {
                        updateNavigationData(sensors)
                    }
                }
            )
    }
    
    private var listContent: some View {
        List {
            motorControlSection
            spotLockSection
            autonomousNavigationSection
            autonomousCommandSection
            connectionSection
            gpsStatusSection
            compassSection
        }
    }

    private var connectionSection: some View {
        Section("Helm Device") {
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

    private var motorControlSection: some View {
        Section {
            motorControlButtons
        } header: {
            Text("Manual Remote Control")
        } footer: {
            Text("Manual control automatically disables autonomous navigation")
        }
    }
    
    private var motorControlButtons: some View {
        VStack(spacing: 16) {
            topButtonRow
            bottomButtonRow
            commandFeedbackView
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private var topButtonRow: some View {
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
    }
    
    private var bottomButtonRow: some View {
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
    
    @ViewBuilder
    private var commandFeedbackView: some View {
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

    private var spotLockSection: some View {
        Section {
            spotLockContent
        } header: {
            Text("Spot Lock")
        } footer: {
            Text("Spot Lock holds MOMENTARY when >2m from lock position. Steering corrections sent when off-course >15°. All logic runs in app.")
        }
    }
    
    @ViewBuilder
    private var spotLockContent: some View {
        if let sensors = bluetooth.sensorData {
            spotLockStatus
            
            if isSpotLockEngaged, let lockPos = spotLockPosition {
                let distance = sensors.currentLocation.distance(to: lockPos)
                LabeledContent("Distance from Lock", value: formatDistance(distance))
                momentaryStatus
                spotLockJogControls
            }
        }
    }
    
    private var spotLockStatus: some View {
        HStack {
            Text(isSpotLockEngaged ? "ACTIVE" : "OFF")
                .foregroundColor(isSpotLockEngaged ? Color.green : .secondary)
            Spacer()
            Button(isSpotLockEngaged ? "Disengage" : "Engage") {
                toggleSpotLock()
            }
            .buttonStyle(.borderedProminent)
            .tint(isSpotLockEngaged ? Color.red : Color.blue)
            .disabled(!canNavigate)
        }
    }
    
    private var momentaryStatus: some View {
        HStack {
            Text("Momentary Status")
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isHoldingMomentary ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(isHoldingMomentary ? "Holding" : "Released")
                    .font(.subheadline)
                    .foregroundColor(isHoldingMomentary ? .green : .secondary)
            }
        }
    }
    
    private var spotLockJogControls: some View {
        VStack(spacing: 8) {
            Text("Jog Position")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Spacer()
                Button(action: { jogSpotLock(direction: .forward) }) {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            HStack(spacing: 16) {
                Button(action: { jogSpotLock(direction: .left) }) {
                    Image(systemName: "arrow.left")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { jogSpotLock(direction: .back) }) {
                    Image(systemName: "arrow.down")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { jogSpotLock(direction: .right) }) {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var autonomousNavigationSection: some View {
        Section {
            autonomousNavContent
        } header: {
            Text("Autonomous Navigation")
        } footer: {
            Text("App calculates all navigation. Helm device only provides sensor data and executes commands.")
        }
    }
    
    @ViewBuilder
    private var autonomousNavContent: some View {
        if let waypoint = selectedWaypoint, let sensors = bluetooth.sensorData {
            waypointInfo(waypoint)
            navigationControls
            navigationMetrics(waypoint: waypoint, sensors: sensors)
        } else {
            Text("No waypoint selected")
                .foregroundColor(.secondary)
        }
    }
    
    private func waypointInfo(_ waypoint: Waypoint) -> some View {
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
    
    private var navigationControls: some View {
        HStack {
            Text(navigationEnabled ? "Navigating" : "Idle")
                .foregroundColor(.secondary)

            Spacer()

            if navigationEnabled {
                Button {
                    stopNavigation()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Navigation")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.red)
            } else {
                Button {
                    if let waypoint = selectedWaypoint {
                        startNavigation(to: waypoint)
                    }
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Navigate to Waypoint")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canNavigate)
            }
        }
    }
    
    private func navigationMetrics(waypoint: Waypoint, sensors: SensorData) -> some View {
        let bearing = sensors.currentLocation.bearing(to: waypoint.coordinate)
        let distance = sensors.currentLocation.distance(to: waypoint.coordinate)
        
        return HStack {
            metricColumn(title: "Bearing", value: String(format: "%.1f°", bearing))
            Spacer()
            metricColumn(title: "Distance", value: formatDistance(distance))
            Spacer()
            metricColumn(title: "Est. Time", value: formatEstimatedTime(distance / (targetSpeedKmh / 3.6)))
        }
    }
    
    private func metricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
    }

    private var autonomousCommandSection: some View {
        Section {
            autonomousCommandContent
        } header: {
            Text("Autonomous Commands")
        } footer: {
            Text("Commands managed by app: 2s intervals, gradual speed changes, steering corrections when off-course >15°")
        }
    }
    
    @ViewBuilder
    private var autonomousCommandContent: some View {
        if navigationEnabled {
            phaseStatusView
            targetSpeedView
            commandStatusView
            powerLevelView
            speedStatusView
        } else {
            Text("Navigation disabled")
                .foregroundColor(.secondary)
        }
    }
    
    private var phaseStatusView: some View {
        HStack {
            Text("Navigation Phase")
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(phaseColor(navigationPhase))
                    .frame(width: 10, height: 10)
                Text(phaseText(navigationPhase))
                    .font(.subheadline.bold())
                    .foregroundColor(phaseColor(navigationPhase))
            }
        }
    }
    
    private var targetSpeedView: some View {
        HStack {
            Text("Target Speed")
                .font(.subheadline)
            Spacer()
            Text(String(format: "%.1f km/hr", targetSpeedKmh))
                .font(.subheadline.bold())
                .foregroundColor(.blue)
        }
    }
    
    private var commandStatusView: some View {
        Group {
            commandRow(
                title: "Steering Command",
                text: steeringCommandDisplayText(steeringCommand),
                color: steeringCommandColor(for: steeringCommand)
            )
            
            Divider()
            
            commandRow(
                title: "Speed Command",
                text: speedCommandDisplayText(speedCommand),
                color: speedCommandColor(for: speedCommand)
            )
        }
    }
    
    private func commandRow(title: String, text: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(text)
                    .font(.subheadline.bold())
                    .foregroundColor(color)
            }
        }
    }
    
    @ViewBuilder
    private var powerLevelView: some View {
        LabeledContent("Power Level", value: "\(currentSpeedLevel)/10")
    }
    
    @ViewBuilder
    private var speedStatusView: some View {
        if let sensors = bluetooth.sensorData {
            let gpsSpeed = sensors.speedKmh
            if gpsSpeed > 0 {
                LabeledContent("GPS Speed", value: String(format: "%.1f km/hr", gpsSpeed))
            }
        }
        if currentSpeedLevel > 0 {
            let estimatedSpeed = Double(currentSpeedLevel) * 0.36
            LabeledContent("Est. Speed", value: String(format: "%.1f km/hr", estimatedSpeed))
        }
    }

    private var gpsStatusSection: some View {
        Section {
            gpsStatusContent
        } header: {
            Text("GPS Status")
        }
    }
    
    @ViewBuilder
    private var gpsStatusContent: some View {
        if let sensors = bluetooth.sensorData {
            gpsQualityRow(sensors)
            LabeledContent("Satellites", value: "\(sensors.satellites)")
            LabeledContent("Accuracy (HDOP)", value: String(format: "%.1f", sensors.hdop))
            
            if sensors.hasFix {
                positionRow(sensors)
            }
        } else {
            Text("No data")
                .foregroundColor(.secondary)
        }
    }
    
    private func gpsQualityRow(_ sensors: SensorData) -> some View {
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
    }
    
    private func positionRow(_ sensors: SensorData) -> some View {
        LabeledContent("Position") {
            Text(String(format: "%.6f, %.6f", sensors.currentLat, sensors.currentLon))
                .font(.caption)
        }
    }

    private var compassSection: some View {
        Section {
            compassContent
        } header: {
            Text("Compass")
        }
    }
    
    @ViewBuilder
    private var compassContent: some View {
        if let sensors = bluetooth.sensorData {
            compassView(sensors)
            LabeledContent("Heading", value: String(format: "%.1f°", sensors.heading))
        } else {
            Text("No data")
                .foregroundColor(.secondary)
        }
    }
    
    private func compassView(_ sensors: SensorData) -> some View {
        HStack {
            Spacer()
            CompassView(heading: sensors.heading, bearing: nil)
                .frame(width: 150, height: 150)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
    
    private func phaseColor(_ phase: NavigationPhase) -> Color {
        switch phase {
        case .idle: return .gray
        case .clearingPowerLevel: return .orange
        case .verifyingMotor: return .yellow
        case .accelerating: return .blue
        case .cruising, .maintaining: return .green
        case .spotLock: return .purple
        case .arrived: return .green
        }
    }
    
    private func phaseText(_ phase: NavigationPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .clearingPowerLevel: return "Clearing Power"
        case .verifyingMotor: return "Verifying Motor"
        case .accelerating: return "Accelerating"
        case .cruising: return "Cruising"
        case .maintaining: return "Maintaining Speed"
        case .spotLock: return "Spot Lock"
        case .arrived: return "Arrived"
        }
    }
}

// MARK: - View Modifier Extensions
private extension View {
    func applyHelmControlToolbar(showingWaypointList: Binding<Bool>) -> some View {
        self.toolbar {
            StatusToolbar {
                showingWaypointList.wrappedValue = true
            }
        }
    }
    
    func applyHelmControlSheets(
        showingWaypointList: Binding<Bool>,
        waypoints: Binding<[Waypoint]>,
        selectedWaypoint: Binding<Waypoint?>,
        navigationEnabled: Binding<Bool>
    ) -> some View {
        self.sheet(isPresented: showingWaypointList) {
            WaypointListView(
                waypoints: waypoints,
                selectedWaypoint: selectedWaypoint,
                navigationEnabled: navigationEnabled
            )
        }
    }
    
    func applyHelmControlAlerts(
        showingArrivalAlert: Binding<Bool>,
        showingError: Binding<Bool>,
        errorMessage: String,
        selectedWaypoint: Waypoint?
    ) -> some View {
        self
            .alert("Arrived!", isPresented: showingArrivalAlert) {
                Button("OK") {
                    showingArrivalAlert.wrappedValue = false
                }
            } message: {
                if let waypoint = selectedWaypoint {
                    Text("You have arrived at \(waypoint.name)")
                }
            }
            .alert("Error", isPresented: showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
    
    func applyHelmControlChangeHandlers(
        navigationEnabled: Binding<Bool>,
        selectedWaypoint: Waypoint?,
        bluetooth: BluetoothManager,
        showingError: Binding<Bool>,
        errorMessage: Binding<String>,
        onNavigationToggle: @escaping (Bool) -> Void,
        onWaypointChange: @escaping () -> Void,
        onConnectionChange: @escaping () -> Void,
        onSensorDataUpdate: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: bluetooth.lastError) { _, error in
                if let error {
                    errorMessage.wrappedValue = error
                    showingError.wrappedValue = true
                }
            }
            .onChange(of: navigationEnabled.wrappedValue) { _, enabled in
                onNavigationToggle(enabled)
            }
            .onChange(of: selectedWaypoint?.id) { _, _ in
                onWaypointChange()
            }
            .onChange(of: bluetooth.connectionState) { _, newState in
                if newState != .connected {
                    onConnectionChange()
                }
            }
            .onChange(of: bluetooth.sensorData) { _, newData in
                if newData != nil {
                    onSensorDataUpdate()
                }
            }
    }
}