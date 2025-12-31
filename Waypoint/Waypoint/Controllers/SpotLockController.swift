import Foundation
import CoreLocation
import Combine

@MainActor
class SpotLockController: ObservableObject {
    
    // MARK: - Published Properties (UI Observable)
    
    @Published var lockPosition: CLLocationCoordinate2D?
    @Published var isActive: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    @Published private(set) var isApplyingThrust: Bool = false
    @Published private(set) var currentCorrectionBearing: Double = 0
    @Published private(set) var currentSpeedLevel: Int = 0
    @Published private(set) var motorState: MotorState = .off
    
    // MARK: - Configuration Constants
    
    private struct Config {
        // Distance thresholds
        static let deadZoneRadius: Double = 2.0              // Stay within this radius
        static let activationThreshold: Double = 4.0         // Start corrections beyond this
        static let hysteresisRatio: Double = 0.5             // Stop at 50% of activation threshold
        static let jogDistance: Double = 1.5                 // Distance for jog movements
        static let maxAcceptableDrift: Double = 6.0          // Warning threshold for drift
        
        // Speed control
        static let minSpeed: Int = 3
        static let maxSpeed: Int = 10
        static let proportionalGain: Double = 0.3            // Speed calculation multiplier
        
        // Steering control
        static let headingTolerance: Double = 30.0           // Degrees off course before steering
        static let smallAngleThreshold: Double = 15.0
        static let largeAngleThreshold: Double = 90.0
        static let minSteeringDuration: Int = 500            // milliseconds
        static let maxSteeringDuration: Int = 1500           // milliseconds
        
        // Timing intervals
        static let correctionInterval: Double = 2.0          // seconds between corrections
        static let progressCheckInterval: Double = 5.0      // seconds between drift checks
        static let speedChangeDelay: Double = 2.0            // seconds between speed changes
        static let steeringReleaseDelay: Int = 200           // milliseconds
        
        // GPS quality requirements
        static let minSatellites: Int = 4
        static let maxHDOP: Double = 5.0
        
        // Position filtering
        static let filterWindowSize: Int = 5
        static let minSamplesForFiltering: Int = 3
    }
    
    // MARK: - Internal State
    
    private let bluetooth: BluetoothManager
    private var lastCorrectionTime: Date?
    private var lastSteeringDirection: SteeringDirection = .none
    private var isMotorOperationInProgress: Bool = false
    
    // Position tracking
    private var positionHistory: [PositionSample] = []
    private var lastProgressCheck: ProgressCheck?
    
    // MARK: - Supporting Types
    
    enum MotorState {
        case off
        case on
        case unknown
    }
    
    enum SteeringDirection {
        case none, left, right
    }
    
    enum JogDirection {
        case forward, back, left, right
        
        var compassHeading: Double {
            switch self {
            case .forward: return 0.0    // North
            case .back: return 180.0     // South
            case .left: return 270.0     // West
            case .right: return 90.0     // East
            }
        }
        
        var compassName: String {
            switch self {
            case .forward: return "North"
            case .back: return "South"
            case .left: return "West"
            case .right: return "East"
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
        // Store the lock position
        lockPosition = position
        isActive = true
        
        // Reset all state
        resetState()
        
        // Log engagement
        log("🎯 ENGAGED at \(formatCoordinate(position))")
        log("   Dead zone: \(Config.deadZoneRadius)m")
        log("   Activation: \(Config.activationThreshold)m")
        log("   Speed range: \(Config.minSpeed)-\(Config.maxSpeed)")
        log("   Heading tolerance: \(Config.headingTolerance)°")
        
        // Prepare motor
        await initializeMotor()
    }
    
    /// Disengages SpotLock and returns control to manual
    func disengage() async {
        guard isActive else { return }
        
        log("⏹️  DISENGAGING...")
        
        // Release any active steering
        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        // Turn off motor if running
        if motorState == .on {
            await setMotorState(.off)
            await setSpeed(0)
        }
        
        // Clear state
        isActive = false
        lockPosition = nil
        resetState()
        
        log("✅ DISENGAGED")
    }
    
    /// Moves the lock position by a small amount in the specified direction
    func jog(direction: JogDirection) {
        guard let currentLock = lockPosition else { return }
        
        // Calculate new position
        let newPosition = calculateDestination(
            from: currentLock,
            heading: direction.compassHeading,
            distance: Config.jogDistance
        )
        
        // Update lock position
        lockPosition = newPosition
        
        // Reset tracking to adapt to new position
        positionHistory.removeAll()
        lastProgressCheck = nil
        
        log("🎮 JOGGED \(direction.compassName) → \(formatCoordinate(newPosition))")
    }
    
    /// Main update loop - call this repeatedly to maintain position
    func update() async {
        guard isActive else { return }
        guard let lockPos = lockPosition else { return }
        guard let sensors = bluetooth.sensorData else { return }
        
        // Check GPS quality
        guard isGPSQualityAcceptable(sensors) else {
            log("⚠️ GPS quality insufficient - disengaging")
            await disengage()
            return
        }
        
        // Get current and filtered positions
        let currentLocation = sensors.currentLocation
        let filteredLocation = addToPositionHistory(currentLocation)
        
        // Use filtered position for distance calculation once we have enough samples
        let locationForDistance = positionHistory.count >= Config.minSamplesForFiltering 
            ? filteredLocation 
            : currentLocation
        distanceFromLock = locationForDistance.distance(to: lockPos)
        
        // Monitor for drift
        checkForDrift()
        
        // Apply corrections if interval has elapsed
        guard shouldApplyCorrection() else { return }
        
        // Decide whether to apply thrust based on distance
        if isApplyingThrust {
            // Check if we're close enough to stop
            if distanceFromLock < (Config.activationThreshold * Config.hysteresisRatio) {
                await stopThrust()
            } else {
                await performCorrection(
                    from: filteredLocation,
                    to: lockPos,
                    heading: sensors.heading
                )
            }
        } else {
            // Check if we've drifted too far and need to start
            if distanceFromLock > Config.activationThreshold {
                await startThrust()
                await performCorrection(
                    from: filteredLocation,
                    to: lockPos,
                    heading: sensors.heading
                )
            }
        }
    }
    
    // MARK: - Motor Control
    
    /// Initializes motor to known state (speed 0, motor on)
    private func initializeMotor() async {
        log("🔧 Initializing motor...")
        
        // Send multiple RF_DOWN commands to ensure speed is 0
        motorState = .unknown
        for _ in 1...10 {
            bluetooth.sendCommand("RF_DOWN")
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        // Set known state
        motorState = .off
        currentSpeedLevel = 0
        
        // Turn motor on and leave at speed 0
        await setMotorState(.on)
        
        log("✅ Motor ready (speed 0)")
    }
    
    /// Sets the motor on or off
    private func setMotorState(_ state: MotorState) async {
        guard !isMotorOperationInProgress else {
            log("⏳ Motor operation in progress - skipping")
            return
        }
        
        guard motorState != state else {
            log("ℹ️  Motor already \(state == .on ? "ON" : "OFF")")
            return
        }
        
        isMotorOperationInProgress = true
        
        log("⚡ Sending RF_MOTOR to turn \(state == .on ? "ON" : "OFF")")
        bluetooth.sendCommand("RF_MOTOR")
        motorState = state
        
        isMotorOperationInProgress = false
    }
    
    /// Changes motor speed gradually to target level
    private func setSpeed(_ targetLevel: Int) async {
        let clampedTarget = targetLevel.clamped(to: 0...Config.maxSpeed)
        guard clampedTarget != currentSpeedLevel else { return }
        
        log("🔼 Speed change: \(currentSpeedLevel) → \(clampedTarget)")
        
        if clampedTarget > currentSpeedLevel {
            // Increase speed
            for _ in currentSpeedLevel..<clampedTarget {
                bluetooth.sendCommand("RF_UP")
                currentSpeedLevel += 1
                try? await Task.sleep(for: .seconds(Config.speedChangeDelay))
            }
        } else {
            // Decrease speed
            for _ in clampedTarget..<currentSpeedLevel {
                bluetooth.sendCommand("RF_DOWN")
                currentSpeedLevel -= 1
                try? await Task.sleep(for: .seconds(Config.speedChangeDelay))
            }
        }
        
        log("✅ Speed set to \(clampedTarget)")
    }
    
    // MARK: - Thrust Management
    
    /// Starts applying thrust to return to lock position
    private func startThrust() async {
        guard !isApplyingThrust else { return }
        guard !isMotorOperationInProgress else {
            log("⏳ Motor operation in progress - skipping startThrust")
            return
        }
        
        // Ensure motor is on
        await setMotorState(.on)
        
        guard motorState == .on else {
            log("❌ ERROR: Failed to turn motor ON")
            return
        }
        
        isApplyingThrust = true
        
        // Set minimum speed if needed
        if currentSpeedLevel < Config.minSpeed {
            await setSpeed(Config.minSpeed)
        }
        
        log("🚀 THRUST START (distance: \(formatDistance(distanceFromLock)), speed: \(currentSpeedLevel))")
    }
    
    /// Stops applying thrust (within dead zone)
    private func stopThrust() async {
        guard isApplyingThrust else { return }
        
        log("🛑 THRUST STOP (within hysteresis: \(formatDistance(distanceFromLock)))")
        
        // Release steering
        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        // Turn off motor
        await setMotorState(.off)
        
        guard motorState == .off else {
            log("❌ ERROR: Failed to turn motor OFF")
            return
        }
        
        // Reset speed
        await setSpeed(0)
        
        isApplyingThrust = false
    }
    
    // MARK: - Correction Logic
    
    /// Performs position correction with steering and speed adjustment
    private func performCorrection(
        from currentLocation: CLLocationCoordinate2D,
        to targetLocation: CLLocationCoordinate2D,
        heading currentHeading: Double
    ) async {
        // Calculate bearing to target
        currentCorrectionBearing = currentLocation.bearing(to: targetLocation)
        
        // Calculate relative angle (how far off course we are)
        let relativeAngle = calculateRelativeAngle(
            currentHeading: currentHeading,
            targetBearing: currentCorrectionBearing
        )
        
        // Determine if we need to steer
        let needsSteering = abs(relativeAngle) > Config.headingTolerance
        
        if needsSteering {
            // Apply steering correction
            let direction: SteeringDirection = relativeAngle > 0 ? .right : .left
            
            // Release opposite direction if needed
            if lastSteeringDirection != .none && lastSteeringDirection != direction {
                await releaseSteering()
            }
            
            await applySteering(direction: direction, angle: relativeAngle)
            
        } else {
            // Heading is good, release steering if active
            if lastSteeringDirection != .none {
                await releaseSteering()
            }
            
            // Adjust speed based on distance
            let distanceBeyondDeadZone = max(0, distanceFromLock - Config.deadZoneRadius)
            let targetSpeed = calculateProportionalSpeed(for: distanceBeyondDeadZone)
            
            if targetSpeed != currentSpeedLevel {
                await setSpeed(targetSpeed)
            }
        }
        
        // Mark correction time
        lastCorrectionTime = Date()
        
        // Log correction details
        log("🧭 CORRECTION: " +
            "dist=\(formatDistance(distanceFromLock)), " +
            "bearing=\(formatAngle(currentCorrectionBearing)), " +
            "heading=\(formatAngle(currentHeading)), " +
            "relative=\(formatAngle(relativeAngle)), " +
            "speed=\(currentSpeedLevel), " +
            "steering=\(needsSteering ? (relativeAngle > 0 ? "RIGHT" : "LEFT") : "NONE")")
    }
    
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
        
        // Hold steering for calculated duration
        try? await Task.sleep(for: .milliseconds(duration))
        
        await releaseSteering()
    }
    
    /// Calculates steering duration based on angle magnitude
    private func calculateSteeringDuration(for absAngle: Double) -> Int {
        if absAngle >= Config.largeAngleThreshold {
            // Large angle: 1200-1500ms
            let ratio = min((absAngle - Config.largeAngleThreshold) / (180.0 - Config.largeAngleThreshold), 1.0)
            return Int(1200 + ratio * 300)
            
        } else if absAngle >= Config.smallAngleThreshold {
            // Medium angle: 700-1200ms
            let ratio = (absAngle - Config.smallAngleThreshold) / (Config.largeAngleThreshold - Config.smallAngleThreshold)
            return Int(700 + ratio * 500)
            
        } else {
            // Small angle: 500-700ms
            let ratio = absAngle / Config.smallAngleThreshold
            return Int(Double(Config.minSteeringDuration) + ratio * 200)
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
        
        // Keep only recent samples
        if positionHistory.count > Config.filterWindowSize {
            positionHistory.removeFirst()
        }
        
        // Need minimum samples for filtering
        guard positionHistory.count >= Config.minSamplesForFiltering else {
            return location
        }
        
        // Calculate average position
        let avgLat = positionHistory.map { $0.coordinate.latitude }.reduce(0, +) / Double(positionHistory.count)
        let avgLon = positionHistory.map { $0.coordinate.longitude }.reduce(0, +) / Double(positionHistory.count)
        
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }
    
    /// Monitors for excessive drift and logs warnings
    private func checkForDrift() {
        let now = Date()
        
        // Initialize on first check
        guard let lastCheck = lastProgressCheck else {
            lastProgressCheck = ProgressCheck(distance: distanceFromLock, timestamp: now)
            return
        }
        
        let timeSinceCheck = now.timeIntervalSince(lastCheck.timestamp)
        
        // Check at intervals
        guard timeSinceCheck >= Config.progressCheckInterval else { return }
        
        let distanceChange = distanceFromLock - lastCheck.distance
        
        if distanceChange > Config.maxAcceptableDrift {
            // Drifting away
            log("⚠️  WARNING: Drifting away! Distance increased by \(formatDistance(distanceChange)) in \(Int(timeSinceCheck))s")
            log("   Check: 1) Motor state, 2) Speed level, 3) Heading alignment")
            
        } else if distanceChange < -2.0 {
            // Making progress
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
        motorState = .off
        positionHistory.removeAll()
        lastCorrectionTime = nil
        lastSteeringDirection = .none
        isMotorOperationInProgress = false
        lastProgressCheck = nil
    }
    
    /// Calculates relative angle from current heading to target bearing
    private func calculateRelativeAngle(currentHeading: Double, targetBearing: Double) -> Double {
        var angle = targetBearing - currentHeading
        
        // Normalize to -180 to +180
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

// MARK: - Extensions

extension Int {
    /// Clamps value to specified range
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}