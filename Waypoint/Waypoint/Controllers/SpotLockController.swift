import Foundation
import CoreLocation
import Combine

@MainActor
class SpotLockController: ObservableObject {
    
    // MARK: - Published Properties (UI Observable)
    
    @Published var lockPosition: CLLocationCoordinate2D?
    @Published var isActive: Bool = false
    @Published private(set) var isDisengaging: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    @Published private(set) var isApplyingThrust: Bool = false
    @Published private(set) var currentCorrectionBearing: Double = 0
    @Published private(set) var currentSpeedLevel: Int = 0
    @Published private(set) var isJogging: Bool = false
    @Published private(set) var cableRotation: Double = 0  // For UI display
    @Published private(set) var isCableTangled: Bool = false
    
    // MARK: - Configuration Constants
    
    private struct Config {
        // Distance thresholds
        static let deadZoneRadius: Double = 2.0
        static let activationThreshold: Double = 4.0
        static let jogDistance: Double = 1.5
        static let maxAcceptableDrift: Double = 6.0
        
        // Speed control
        static let minSpeed: Int = 3
        static let maxSpeed: Int = 10
        static let proportionalGain: Double = 1.0
        
        // Steering control
        static let headingTolerance: Double = 10.0
        static let smallAngleThreshold: Double = 30.0
        static let largeAngleThreshold: Double = 90.0
        static let smallSteeringDuration: Int = 200
        static let mediumSteeringDuration: Int = 600
        static let largeSteeringDuration: Int = 1000
        
        // Cable tangle prevention
        static let maxRotationBeforeUntangle: Double = 720.0  // 2 full rotations
        static let rotationPerMs: Double = 0.1  // Estimated degrees per ms of steering
        
        // Timing intervals
        static let correctionInterval: Double = 1.0
        static let progressCheckInterval: Double = 5.0
        static let speedChangeDelay: Double = 2.0
        static let steeringReleaseDelay: Int = 200
        
        // GPS quality requirements
        static let minSatellites: Int = 4
        static let maxHDOP: Double = 5.0
        static let maxConsecutiveGpsFailures: Int = 5  // Allow 5 consecutive failures before disengaging
        
        // Position filtering
        static let filterWindowSize: Int = 5
        static let minSamplesForFiltering: Int = 3
    }
    
    // MARK: - Internal State
    
    private let bluetooth: BluetoothManager
    private var lastCorrectionTime: Date?
    private var lastSteeringDirection: SteeringDirection = .none
    private var jogHoldTimer: Timer?
    private var currentJogDirection: JogDirection?
    private var isSpeedChangeInProgress: Bool = false
    private var targetSpeedLevel: Int = 0
    
    // Position tracking
    private var positionHistory: [PositionSample] = []
    private var lastProgressCheck: ProgressCheck?
    
    // Cable tangle prevention
    private var cumulativeRotation: Double = 0  // Positive = right, negative = left
    private var isUntangling: Bool = false
    
    // GPS quality tracking
    private var consecutiveGpsFailures: Int = 0
    
    // MARK: - Supporting Types
    
    enum SteeringDirection {
        case none, left, right
    }
    
    enum JogDirection {
        case forward, back, left, right
        
        var compassHeading: Double {
            switch self {
            case .forward: return 0.0
            case .right: return 90.0
            case .back: return 180.0
            case .left: return 270.0
            }
        }
        
        var compassName: String {
            switch self {
            case .forward: return "North"
            case .right: return "East"
            case .back: return "South"
            case .left: return "West"
            }
        }
    }
    
    private struct PositionSample {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }
    
    private struct ProgressCheck {
        let distance: Double
        let timestamp: Date
    }
    
    // MARK: - Initialization
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
    }
    
    // MARK: - Public API
    
    /// Engages SpotLock at the specified position
    func engage(at position: CLLocationCoordinate2D) async {
        lockPosition = position
        isActive = true
        
        resetState()
        
        log("🎯 ENGAGED at \(formatCoordinate(position))")
        log("   Dead zone: \(Config.deadZoneRadius)m")
        log("   Activation: \(Config.activationThreshold)m")
        log("   Speed range: \(Config.minSpeed)-\(Config.maxSpeed)")
        log("   Heading tolerance: \(Config.headingTolerance)°")
        log("   Steering durations: <30°=\(Config.smallSteeringDuration)ms, 30-90°=\(Config.mediumSteeringDuration)ms, >90°=\(Config.largeSteeringDuration)ms")
        log("   Max rotation before untangle: \(Config.maxRotationBeforeUntangle)°")
        
        await ensureSpeedIsZero()
    }
    
    /// Disengages SpotLock and returns control to manual
    func disengage() async {
        guard isActive else { return }
        
        isDisengaging = true
        log("ℹ️  DISENGAGING...")
        
        stopJogHold()
        
        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        if isApplyingThrust {
            isSpeedChangeInProgress = false
            targetSpeedLevel = 0
            
            await stopThrust()
        }
        
        isActive = false
        lockPosition = nil
        resetState()
        
        isDisengaging = false
        log("✅ DISENGAGED")
    }
    
    /// Starts jogging in the specified direction (call when button pressed)
    func jogStart(direction: JogDirection) {
        guard lockPosition != nil else { return }
        
        stopJogHold()
        
        currentJogDirection = direction
        isJogging = true
        
        performJog(direction: direction)
        
        jogHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let dir = self.currentJogDirection else { return }
                self.performJog(direction: dir)
            }
        }
        
        log("🎮 JOG START \(direction.compassName)")
    }
    
    /// Stops jogging (call when button released)
    func jogStop() {
        guard isJogging else { return }
        
        stopJogHold()
        log("🎮 JOG STOP")
    }
    
    private func stopJogHold() {
        jogHoldTimer?.invalidate()
        jogHoldTimer = nil
        currentJogDirection = nil
        isJogging = false
    }
    
    private func performJog(direction: JogDirection) {
        guard let currentLock = lockPosition else { return }
        
        let newPosition = calculateDestination(
            from: currentLock,
            heading: direction.compassHeading,
            distance: Config.jogDistance
        )
        
        lockPosition = newPosition
        positionHistory.removeAll()
        lastProgressCheck = nil
    }
    
    /// Main update loop - call this repeatedly to maintain position
    func update() async {
        guard isActive else { return }
        guard let lockPos = lockPosition else { return }
        
        guard let sensors = bluetooth.sensorData else {
            consecutiveGpsFailures += 1
            log("⚠️ No sensor data (failure \(consecutiveGpsFailures)/\(Config.maxConsecutiveGpsFailures))")
            
            if consecutiveGpsFailures >= Config.maxConsecutiveGpsFailures {
                log("⚠️ GPS data unavailable - disengaging")
                await disengage()
            }
            return
        }
        
        if !isGPSQualityAcceptable(sensors) {
            consecutiveGpsFailures += 1
            log("⚠️ GPS quality check failed (failure \(consecutiveGpsFailures)/\(Config.maxConsecutiveGpsFailures)): " +
                "hasFix=\(sensors.hasFix), satellites=\(sensors.satellites), hdop=\(sensors.hdop)")
            
            if consecutiveGpsFailures >= Config.maxConsecutiveGpsFailures {
                log("⚠️ GPS quality insufficient - disengaging")
                await disengage()
            }
            return
        }
        
        // GPS quality is good - reset failure counter
        consecutiveGpsFailures = 0
        
        let currentLocation = sensors.currentLocation
        let filteredLocation = addToPositionHistory(currentLocation)
        
        let locationForDistance = positionHistory.count >= Config.minSamplesForFiltering 
            ? filteredLocation 
            : currentLocation
        distanceFromLock = locationForDistance.distance(to: lockPos)
        
        checkForDrift()
        
        // Calculate bearing FROM current position TO lock position
        // This gives us the heading we need to travel to reach the lock
        currentCorrectionBearing = filteredLocation.bearing(to: lockPos)
        
        let relativeAngle = calculateRelativeAngle(
            currentHeading: sensors.heading,
            targetBearing: currentCorrectionBearing
        )
        
        guard shouldApplyCorrection() else { return }
        
        // Mark correction time to prevent concurrent corrections
        lastCorrectionTime = Date()
        
        // Check if we need to untangle the cable
        let needsUntangle = abs(cumulativeRotation) > Config.maxRotationBeforeUntangle
        
        // Apply steering correction BEFORE thrust (align first)
        let needsSteering = abs(relativeAngle) > Config.headingTolerance
        
        if needsUntangle {
            // Force steering in opposite direction to untangle
            let untangleDirection: SteeringDirection = cumulativeRotation > 0 ? .left : .right
            
            if !isUntangling {
                isUntangling = true
                isCableTangled = true
                log("⚠️ CABLE TANGLE DETECTED - Rotation: \(formatAngle(cumulativeRotation)) - Forcing \(untangleDirection == .left ? "LEFT" : "RIGHT") to untangle")
            }
            
            if lastSteeringDirection != .none && lastSteeringDirection != untangleDirection {
                await releaseSteering()
            }
            
            await applySteering(direction: untangleDirection, angle: 90.0)  // Use medium duration
            
        } else if needsSteering {
            if isUntangling {
                isUntangling = false
                isCableTangled = false
                log("✅ CABLE UNTANGLED - Resuming normal steering")
            }
            
            let direction: SteeringDirection = relativeAngle > 0 ? .right : .left
            
            if lastSteeringDirection != .none && lastSteeringDirection != direction {
                await releaseSteering()
            }
            
            await applySteering(direction: direction, angle: relativeAngle)
        } else if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        // Start or stop thrust based on distance
        if distanceFromLock > Config.activationThreshold {
            if !isApplyingThrust {
                await startThrust()
            }
        } else if distanceFromLock < Config.deadZoneRadius {
            if isApplyingThrust {
                await stopThrust()
            }
        }
        
        // Adjust speed if thrusting
        if isApplyingThrust {
            let distanceBeyondDeadZone = max(0, distanceFromLock - Config.deadZoneRadius)
            let targetSpeed = calculateProportionalSpeed(for: distanceBeyondDeadZone)
            
            if targetSpeed != targetSpeedLevel {
                Task {
                    await setSpeed(targetSpeed)
                }
            }
        }
        
        log("🧭 CORRECTION: " +
            "dist=\(formatDistance(distanceFromLock)), " +
            "bearing=\(formatAngle(currentCorrectionBearing)), " +
            "heading=\(formatAngle(sensors.heading)), " +
            "relative=\(formatAngle(relativeAngle)), " +
            "speed=\(currentSpeedLevel)/\(targetSpeedLevel), " +
            "steering=\(needsSteering || needsUntangle ? (isUntangling ? "UNTANGLE-" : "") + (cumulativeRotation > 0 || relativeAngle > 0 ? "RIGHT" : "LEFT") : "NONE"), " +
            "rotation=\(formatAngle(cumulativeRotation))")
    }
    
    // MARK: - Motor Control
    
    /// Ensures motor speed is at 0 by sending multiple RF_DOWN commands
    private func ensureSpeedIsZero() async {
        log("🔧 Ensuring speed is 0...")
        
        isSpeedChangeInProgress = false
        targetSpeedLevel = 0
        currentSpeedLevel = 0
        
        for _ in 1...10 {
            bluetooth.sendCommand("RF_DOWN")
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        log("✅ Speed set to 0")
    }
    
    /// Changes motor speed gradually to target level
    private func setSpeed(_ targetLevel: Int) async {
        let clampedTarget = max(0, min(targetLevel, Config.maxSpeed))
        guard clampedTarget != currentSpeedLevel else { return }
        guard !isSpeedChangeInProgress else {
            targetSpeedLevel = clampedTarget
            return
        }
        
        isSpeedChangeInProgress = true
        targetSpeedLevel = clampedTarget
        
        log("🔼 Speed change: \(currentSpeedLevel) → \(clampedTarget)")
        
        while currentSpeedLevel != targetSpeedLevel && isSpeedChangeInProgress {
            if targetSpeedLevel > currentSpeedLevel {
                bluetooth.sendCommand("RF_UP")
                currentSpeedLevel = min(currentSpeedLevel + 1, Config.maxSpeed)
            } else {
                bluetooth.sendCommand("RF_DOWN")
                currentSpeedLevel = max(currentSpeedLevel - 1, 0)
            }
            try? await Task.sleep(for: .seconds(Config.speedChangeDelay))
        }
        
        isSpeedChangeInProgress = false
        log("✅ Speed set to \(currentSpeedLevel)")
    }
    
    // MARK: - Thrust Management
    
    /// Starts applying thrust to return to lock position
    private func startThrust() async {
        guard !isApplyingThrust else { return }
        
        isApplyingThrust = true
        
        if currentSpeedLevel < Config.minSpeed {
            Task {
                await setSpeed(Config.minSpeed)
            }
        }
        
        log("🚀 THRUST START (distance: \(formatDistance(distanceFromLock)), speed: \(currentSpeedLevel))")
    }
    
    /// Stops applying thrust (within dead zone)
    private func stopThrust() async {
        guard isApplyingThrust else { return }
        
        log("🛑 THRUST STOP (within dead zone: \(formatDistance(distanceFromLock)))")
        
        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        isSpeedChangeInProgress = false
        targetSpeedLevel = 0
        
        Task {
            await setSpeed(0)
        }
        
        isApplyingThrust = false
    }
    
    // MARK: - Speed Calculation
    
    /// Calculates proportional speed based on distance from dead zone
    private func calculateProportionalSpeed(for distanceBeyondDeadZone: Double) -> Int {
        guard distanceBeyondDeadZone > 0 else { return Config.minSpeed }
        
        let rawSpeed = distanceBeyondDeadZone * Config.proportionalGain + Double(Config.minSpeed)
        let clampedSpeed = min(rawSpeed, Double(Config.maxSpeed))
        
        return max(Config.minSpeed, Int(round(clampedSpeed)))
    }
    
    // MARK: - Steering Control
    
    /// Applies steering in the specified direction with duration based on angle
    private func applySteering(direction: SteeringDirection, angle: Double) async {
        guard direction != .none else { return }
        
        let command = direction == .left ? "RF_LEFT_HOLD" : "RF_RIGHT_HOLD"
        let duration = calculateSteeringDuration(for: abs(angle))
        
        bluetooth.sendCommand(command)
        lastSteeringDirection = direction
        
        // Track cumulative rotation for cable tangle prevention
        let rotationAmount = Double(duration) * Config.rotationPerMs
        if direction == .right {
            cumulativeRotation += rotationAmount
        } else {
            cumulativeRotation -= rotationAmount
        }
        
        // Update published properties for UI
        cableRotation = cumulativeRotation
        isCableTangled = abs(cumulativeRotation) > Config.maxRotationBeforeUntangle
        
        try? await Task.sleep(for: .milliseconds(duration))
        
        await releaseSteering()
    }
    
    /// Calculates steering duration based on angle magnitude
    private func calculateSteeringDuration(for absAngle: Double) -> Int {
        if absAngle >= Config.largeAngleThreshold {
            return Config.largeSteeringDuration
        } else if absAngle >= Config.smallAngleThreshold {
            return Config.mediumSteeringDuration
        } else {
            return Config.smallSteeringDuration
        }
    }
    
    /// Releases steering control
    private func releaseSteering() async {
        guard lastSteeringDirection != .none else { return }
        
        bluetooth.sendCommand("RF_RELEASE")
        lastSteeringDirection = .none
        
        try? await Task.sleep(for: .milliseconds(Config.steeringReleaseDelay))
    }
    
    // MARK: - Position Tracking
    
    /// Adds position to history and returns filtered position
    private func addToPositionHistory(_ location: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let sample = PositionSample(coordinate: location, timestamp: Date())
        positionHistory.append(sample)
        
        if positionHistory.count > Config.filterWindowSize {
            positionHistory.removeFirst()
        }
        
        guard positionHistory.count >= Config.minSamplesForFiltering else {
            return location
        }
        
        let avgLat = positionHistory.map { $0.coordinate.latitude }.reduce(0, +) / Double(positionHistory.count)
        let avgLon = positionHistory.map { $0.coordinate.longitude }.reduce(0, +) / Double(positionHistory.count)
        
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }
    
    /// Monitors for excessive drift and logs warnings
    private func checkForDrift() {
        let now = Date()
        
        guard let lastCheck = lastProgressCheck else {
            lastProgressCheck = ProgressCheck(distance: distanceFromLock, timestamp: now)
            return
        }
        
        let timeSinceCheck = now.timeIntervalSince(lastCheck.timestamp)
        
        guard timeSinceCheck >= Config.progressCheckInterval else { return }
        
        let distanceChange = distanceFromLock - lastCheck.distance
        
        if distanceChange > Config.maxAcceptableDrift {
            log("⚠️  WARNING: Drifting away! Distance increased by \(formatDistance(distanceChange)) in \(Int(timeSinceCheck))s")
            log("   Check: 1) Motor state, 2) Speed level, 3) Heading alignment")
        } else if distanceChange < -2.0 {
            log("✅ Making progress: Distance decreased by \(formatDistance(-distanceChange))")
        }
        
        lastProgressCheck = ProgressCheck(distance: distanceFromLock, timestamp: now)
    }
    
    // MARK: - Validation & Timing
    
    /// Checks if GPS quality is acceptable
    private func isGPSQualityAcceptable(_ sensors: SensorData) -> Bool {
        return sensors.hasFix && 
               sensors.satellites >= Config.minSatellites && 
               sensors.hdop < Config.maxHDOP
    }
    
    /// Checks if enough time has passed since last correction
    private func shouldApplyCorrection() -> Bool {
        guard let lastTime = lastCorrectionTime else { return true }
        return Date().timeIntervalSince(lastTime) >= Config.correctionInterval
    }
    
    // MARK: - Helper Methods
    
    /// Resets all internal state
    private func resetState() {
        distanceFromLock = 0
        isApplyingThrust = false
        currentSpeedLevel = 0
        targetSpeedLevel = 0
        isSpeedChangeInProgress = false
        positionHistory.removeAll()
        lastCorrectionTime = nil
        lastSteeringDirection = .none
        lastProgressCheck = nil
        cumulativeRotation = 0
        cableRotation = 0
        isUntangling = false
        isCableTangled = false
        consecutiveGpsFailures = 0
        stopJogHold()
    }
    
    /// Calculates relative angle from current heading to target bearing
    private func calculateRelativeAngle(currentHeading: Double, targetBearing: Double) -> Double {
        var angle = targetBearing - currentHeading
        
        while angle > 180 {
            angle -= 360
        }
        while angle < -180 {
            angle += 360
        }
        
        return angle
    }
    
    /// Calculates destination coordinate from origin, heading, and distance
    private func calculateDestination(
        from position: CLLocationCoordinate2D,
        heading: Double,
        distance: Double
    ) -> CLLocationCoordinate2D {
        let headingRad = heading * .pi / 180.0
        let metersPerDegLat = 111320.0
        
        let deltaLat = (distance / metersPerDegLat) * cos(headingRad)
        let deltaLon = (distance / (metersPerDegLat * cos(position.latitude * .pi / 180.0))) * sin(headingRad)
        
        return CLLocationCoordinate2D(
            latitude: position.latitude + deltaLat,
            longitude: position.longitude + deltaLon
        )
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCoordinate(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coord.latitude, coord.longitude)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.2fm", meters)
    }
    
    private func formatAngle(_ degrees: Double) -> String {
        String(format: "%.1f°", degrees)
    }
    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}