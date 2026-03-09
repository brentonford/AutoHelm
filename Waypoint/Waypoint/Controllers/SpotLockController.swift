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
    @Published private(set) var cableRotation: Double = 0
    @Published private(set) var isCableTangled: Bool = false

    // MARK: - Internal (Non-User-Configurable) Constants

    private struct InternalConfig {
        /// Untangle procedure steers opposite until cumulative rotation drops below this level.
        static let safeRotationLevel: Double = 360.0
        /// Milliseconds to pause after releasing a steering hold before the next command.
        static let steeringReleaseDelay: Int = 200
        /// Seconds between drift-progress log checks.
        static let progressCheckInterval: Double = 5.0
        /// Metres of drift increase per check period that triggers a warning log.
        static let maxAcceptableDrift: Double = 6.0
        /// HDOP value returned by GPS hardware when data is invalid (not a real accuracy reading).
        static let invalidHDOP: Double = 99.0
        /// Minimum position history samples required before the average filter is applied.
        static let minSamplesForFiltering: Int = 3
    }

    // MARK: - Internal State

    private let bluetooth: BluetoothManager
    /// User-configurable settings captured from DataStore when Spot Lock is engaged.
    private var settings: SpotLockSettings = SpotLockSettings()

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
    private var cumulativeRotation: Double = 0
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
            case .right:   return 90.0
            case .back:    return 180.0
            case .left:    return 270.0
            }
        }

        var compassName: String {
            switch self {
            case .forward: return "North"
            case .right:   return "East"
            case .back:    return "South"
            case .left:    return "West"
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

    /// Engages SpotLock at the specified position, capturing current settings from DataStore.
    func engage(at position: CLLocationCoordinate2D) async {
        settings = DataStore.shared.spotLockSettings

        lockPosition = position
        isActive = true

        resetState()

        log("🎯 ENGAGED at \(formatCoordinate(position))")
        log("   Dead zone: \(settings.deadZoneRadius)m, Activation: \(settings.activationThreshold)m")
        log("   Speed range: \(settings.minSpeed)-\(settings.maxSpeed), Gain: \(settings.proportionalGain)×")
        log("   Heading tolerance: \(settings.headingTolerance)°, Correction interval: \(settings.correctionInterval)s")
        log("   Steering durations: <\(Int(settings.smallAngleThreshold))°=\(settings.smallSteeringDuration)ms, \(Int(settings.smallAngleThreshold))-\(Int(settings.largeAngleThreshold))°=\(settings.mediumSteeringDuration)ms, >\(Int(settings.largeAngleThreshold))°=\(settings.largeSteeringDuration)ms")
        log("   Cable untangle: starts >\(settings.maxRotationBeforeUntangle)°, stops <\(InternalConfig.safeRotationLevel)°, \(settings.rotationPerMs)°/ms")
        log("   GPS: min \(settings.minSatellites) sats, max HDOP \(settings.maxHDOP), tolerance \(settings.maxConsecutiveGpsFailures) failures")
        log("   Filter window: \(settings.filterWindowSize) samples, Jog distance: \(settings.jogDistance)m")

        await ensureSpeedIsZero()
    }

    /// Disengages SpotLock and returns control to manual.
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

    /// Starts jogging in the specified direction (call when button pressed).
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

    /// Stops jogging (call when button released).
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
            distance: settings.jogDistance
        )

        lockPosition = newPosition
        positionHistory.removeAll()
        lastProgressCheck = nil
    }

    /// Main update loop — call this repeatedly to maintain position.
    func update() async {
        guard isActive else { return }
        guard let lockPos = lockPosition else { return }

        guard let sensors = bluetooth.sensorData else {
            consecutiveGpsFailures += 1
            log("⚠️ No sensor data (failure \(consecutiveGpsFailures)/\(settings.maxConsecutiveGpsFailures))")

            if consecutiveGpsFailures >= settings.maxConsecutiveGpsFailures {
                log("⚠️ GPS data unavailable - disengaging")
                await disengage()
            }
            return
        }

        if !isGPSQualityAcceptable(sensors) {
            consecutiveGpsFailures += 1

            var failureReason = ""
            if !sensors.hasFix {
                failureReason = "no fix"
            } else if sensors.satellites < settings.minSatellites {
                failureReason = "low satellites (\(sensors.satellites))"
            } else if sensors.hdop >= InternalConfig.invalidHDOP {
                failureReason = "invalid HDOP (\(sensors.hdop))"
            } else if sensors.hdop >= settings.maxHDOP {
                failureReason = "high HDOP (\(sensors.hdop))"
            }

            log("⚠️ GPS quality check failed (failure \(consecutiveGpsFailures)/\(settings.maxConsecutiveGpsFailures)): \(failureReason)")

            if consecutiveGpsFailures >= settings.maxConsecutiveGpsFailures {
                log("⚠️ GPS quality insufficient - disengaging")
                await disengage()
            }
            return
        }

        consecutiveGpsFailures = 0

        let currentLocation = sensors.currentLocation
        let filteredLocation = addToPositionHistory(currentLocation)

        let locationForDistance = positionHistory.count >= InternalConfig.minSamplesForFiltering
            ? filteredLocation
            : currentLocation
        distanceFromLock = locationForDistance.distance(to: lockPos)

        checkForDrift()

        currentCorrectionBearing = filteredLocation.bearing(to: lockPos)

        let relativeAngle = calculateRelativeAngle(
            currentHeading: sensors.heading,
            targetBearing: currentCorrectionBearing
        )

        guard shouldApplyCorrection() else { return }

        lastCorrectionTime = Date()

        let absRotation = abs(cumulativeRotation)
        let shouldStartUntangle = absRotation > settings.maxRotationBeforeUntangle
        let shouldContinueUntangle = isUntangling && absRotation > InternalConfig.safeRotationLevel
        let needsUntangle = shouldStartUntangle || shouldContinueUntangle

        let untangleDirection: SteeringDirection = cumulativeRotation > 0 ? .left : .right

        let needsSteering = abs(relativeAngle) > settings.headingTolerance

        let actualSteeringDirection: String

        if needsUntangle {
            if !isUntangling {
                isUntangling = true
                isCableTangled = true
                log("⚠️ CABLE TANGLE DETECTED - Rotation: \(formatAngle(cumulativeRotation)) - Forcing \(untangleDirection == .left ? "LEFT" : "RIGHT") to untangle until \(formatAngle(InternalConfig.safeRotationLevel))")
            }

            actualSteeringDirection = "UNTANGLE-\(untangleDirection == .left ? "LEFT" : "RIGHT")"

            if lastSteeringDirection != .none && lastSteeringDirection != untangleDirection {
                await releaseSteering()
            }

            await applySteering(direction: untangleDirection, angle: 90.0)

        } else if needsSteering {
            if isUntangling {
                isUntangling = false
                isCableTangled = false
                log("✅ CABLE UNTANGLED - Rotation: \(formatAngle(cumulativeRotation)) - Resuming normal steering")
            }

            let direction: SteeringDirection = relativeAngle > 0 ? .right : .left
            actualSteeringDirection = direction == .right ? "RIGHT" : "LEFT"

            if lastSteeringDirection != .none && lastSteeringDirection != direction {
                await releaseSteering()
            }

            await applySteering(direction: direction, angle: relativeAngle)

        } else {
            if isUntangling {
                isUntangling = false
                isCableTangled = false
                log("✅ CABLE UNTANGLED - Rotation: \(formatAngle(cumulativeRotation)) - Resuming normal steering")
            }

            actualSteeringDirection = "NONE"

            if lastSteeringDirection != .none {
                await releaseSteering()
            }
        }

        if distanceFromLock > settings.activationThreshold {
            if !isApplyingThrust {
                await startThrust()
            }
        } else if distanceFromLock < settings.deadZoneRadius {
            if isApplyingThrust {
                await stopThrust()
            }
        }

        if isApplyingThrust {
            let distanceBeyondDeadZone = max(0, distanceFromLock - settings.deadZoneRadius)
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
            "steering=\(actualSteeringDirection), " +
            "rotation=\(formatAngle(cumulativeRotation))")
    }

    // MARK: - Motor Control

    /// Ensures motor speed is at 0 by sending multiple RF_DOWN commands.
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

    /// Changes motor speed gradually to target level.
    private func setSpeed(_ targetLevel: Int) async {
        let clampedTarget = max(0, min(targetLevel, settings.maxSpeed))
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
                currentSpeedLevel = min(currentSpeedLevel + 1, settings.maxSpeed)
            } else {
                bluetooth.sendCommand("RF_DOWN")
                currentSpeedLevel = max(currentSpeedLevel - 1, 0)
            }
            try? await Task.sleep(for: .seconds(settings.speedChangeDelay))
        }

        isSpeedChangeInProgress = false
        log("✅ Speed set to \(currentSpeedLevel)")
    }

    // MARK: - Thrust Management

    private func startThrust() async {
        guard !isApplyingThrust else { return }

        isApplyingThrust = true

        if currentSpeedLevel < settings.minSpeed {
            Task {
                await setSpeed(settings.minSpeed)
            }
        }

        log("🚀 THRUST START (distance: \(formatDistance(distanceFromLock)), speed: \(currentSpeedLevel))")
    }

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

    private func calculateProportionalSpeed(for distanceBeyondDeadZone: Double) -> Int {
        guard distanceBeyondDeadZone > 0 else { return settings.minSpeed }

        let rawSpeed = distanceBeyondDeadZone * settings.proportionalGain + Double(settings.minSpeed)
        let clampedSpeed = min(rawSpeed, Double(settings.maxSpeed))

        return max(settings.minSpeed, Int(round(clampedSpeed)))
    }

    // MARK: - Steering Control

    private func applySteering(direction: SteeringDirection, angle: Double) async {
        guard direction != .none else { return }

        let command = direction == .left ? "RF_LEFT_HOLD" : "RF_RIGHT_HOLD"
        let duration = calculateSteeringDuration(for: abs(angle))

        bluetooth.sendCommand(command)
        lastSteeringDirection = direction

        let rotationAmount = Double(duration) * settings.rotationPerMs
        if direction == .right {
            cumulativeRotation += rotationAmount
        } else {
            cumulativeRotation -= rotationAmount
        }

        cableRotation = cumulativeRotation
        isCableTangled = abs(cumulativeRotation) > settings.maxRotationBeforeUntangle

        try? await Task.sleep(for: .milliseconds(duration))

        await releaseSteering()
    }

    private func calculateSteeringDuration(for absAngle: Double) -> Int {
        if absAngle >= settings.largeAngleThreshold {
            return settings.largeSteeringDuration
        } else if absAngle >= settings.smallAngleThreshold {
            return settings.mediumSteeringDuration
        } else {
            return settings.smallSteeringDuration
        }
    }

    private func releaseSteering() async {
        guard lastSteeringDirection != .none else { return }

        bluetooth.sendCommand("RF_RELEASE")
        lastSteeringDirection = .none

        try? await Task.sleep(for: .milliseconds(InternalConfig.steeringReleaseDelay))
    }

    // MARK: - Position Tracking

    private func addToPositionHistory(_ location: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let sample = PositionSample(coordinate: location, timestamp: Date())
        positionHistory.append(sample)

        if positionHistory.count > settings.filterWindowSize {
            positionHistory.removeFirst()
        }

        guard positionHistory.count >= InternalConfig.minSamplesForFiltering else {
            return location
        }

        let avgLat = positionHistory.map { $0.coordinate.latitude }.reduce(0, +) / Double(positionHistory.count)
        let avgLon = positionHistory.map { $0.coordinate.longitude }.reduce(0, +) / Double(positionHistory.count)

        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }

    private func checkForDrift() {
        let now = Date()

        guard let lastCheck = lastProgressCheck else {
            lastProgressCheck = ProgressCheck(distance: distanceFromLock, timestamp: now)
            return
        }

        let timeSinceCheck = now.timeIntervalSince(lastCheck.timestamp)

        guard timeSinceCheck >= InternalConfig.progressCheckInterval else { return }

        let distanceChange = distanceFromLock - lastCheck.distance

        if distanceChange > InternalConfig.maxAcceptableDrift {
            log("⚠️  WARNING: Drifting away! Distance increased by \(formatDistance(distanceChange)) in \(Int(timeSinceCheck))s")
            log("   Check: 1) Motor state, 2) Speed level, 3) Heading alignment")
        } else if distanceChange < -2.0 {
            log("✅ Making progress: Distance decreased by \(formatDistance(-distanceChange))")
        }

        lastProgressCheck = ProgressCheck(distance: distanceFromLock, timestamp: now)
    }

    // MARK: - Validation & Timing

    private func isGPSQualityAcceptable(_ sensors: SensorData) -> Bool {
        guard sensors.hasFix else { return false }
        guard sensors.satellites >= settings.minSatellites else { return false }

        if sensors.hdop < InternalConfig.invalidHDOP && sensors.hdop >= settings.maxHDOP {
            return false
        }

        return true
    }

    private func shouldApplyCorrection() -> Bool {
        guard let lastTime = lastCorrectionTime else { return true }
        return Date().timeIntervalSince(lastTime) >= settings.correctionInterval
    }

    // MARK: - Helper Methods

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

    private func calculateRelativeAngle(currentHeading: Double, targetBearing: Double) -> Double {
        var angle = targetBearing - currentHeading

        while angle > 180  { angle -= 360 }
        while angle < -180 { angle += 360 }

        return angle
    }

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
