import Foundation
import CoreLocation
import Combine

@MainActor
class SpotLockController: ObservableObject {
    
    @Published var lockPosition: CLLocationCoordinate2D?
    @Published var isActive: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    @Published private(set) var isApplyingThrust: Bool = false
    @Published private(set) var currentCorrectionBearing: Double = 0
    @Published private(set) var currentSpeedLevel: Int = 0
    @Published private(set) var motorState: MotorState = .unknown
    
    private let bluetooth: BluetoothManager
    
    private var isMotorOperationInProgress: Bool = false
    private var lastSteeringDirection: SteeringDirection = .none
    
    private let deadZoneRadiusMeters: Double = 2.0
    private let activationThresholdMeters: Double = 4.0
    private let hysteresisRatio: Double = 0.5
    private let jogDistanceMeters: Double = 1.5
    private let minCorrectionSpeed: Int = 3
    private let maxCorrectionSpeed: Int = 5
    private let minSpeedForLargeAngle: Int = 3
    private let headingToleranceDegrees: Double = 30.0
    private let steeringHoldDurationMs: Int = 500
    private let minSteeringDurationMs: Int = 500
    private let mediumSteeringDurationMs: Int = 800  
    private let maxSteeringDurationMs: Int = 1500
    private let largeAngleThreshold: Double = 90.0
    private let mediumAngleThreshold: Double = 45.0
    private let headingToleranceDegrees: Double = 45.0
    private let correctionIntervalSeconds: Double = 2.0

    
    private var positionHistory: [FilteredPosition] = []
    private let filterWindowSize: Int = 5
    private var lastCorrectionTime: Date?
    private let correctionIntervalSeconds: Double = 3.0
    
    private var lastDistanceCheck: Date?
    private var lastDistanceValue: Double = 0
    private let progressCheckIntervalSeconds: Double = 10.0
    private let maxAcceptableDrift: Double = 5.0
    
    private var speedHistory: [SpeedSample] = []
    private let speedHistorySize: Int = 10
    private let initialMotorValidationDelaySeconds: Double = 2.0
    private let speedChangeDelaySeconds: Double = 1.0
    private let movementThresholdKmh: Double = 3.5
    
    private struct FilteredPosition {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }
    
    private struct SpeedSample {
        let speedKmh: Double
        let timestamp: Date
    }
    
    enum MotorState {
        case unknown
        case motorOff
        case motorOn
        case validating
    }
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
    }
    
    func engage(at position: CLLocationCoordinate2D) async {
        lockPosition = position
        isActive = true
        isApplyingThrust = false
        distanceFromLock = 0
        positionHistory.removeAll()
        speedHistory.removeAll()
        lastCorrectionTime = nil
        currentSpeedLevel = 0
        motorState = .unknown
        isMotorOperationInProgress = false
        lastSteeringDirection = .none
        lastDistanceCheck = nil
        lastDistanceValue = 0
        
        logWithTime("[SpotLock] Engaged at \(String(format: "%.6f, %.6f", position.latitude, position.longitude))")
        logWithTime("[SpotLock] Dead zone: \(deadZoneRadiusMeters)m, Activation: \(activationThresholdMeters)m, Hysteresis: \(activationThresholdMeters * hysteresisRatio)m")
        logWithTime("[SpotLock] Min speed: \(minCorrectionSpeed), Max speed: \(maxCorrectionSpeed), Heading tolerance: \(headingToleranceDegrees)°")
        
        await ensureMotorReady()
    }
    
    func disengage() async {
        guard isActive else { return }
        
        logWithTime("[SpotLock] Disengaging...")
        
        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        if motorState == .motorOn {
            await turnMotorOff()
        }
        
        isActive = false
        lockPosition = nil
        distanceFromLock = 0
        positionHistory.removeAll()
        speedHistory.removeAll()
        lastCorrectionTime = nil
        isMotorOperationInProgress = false
        lastSteeringDirection = .none
        lastDistanceCheck = nil
        lastDistanceValue = 0
        
        logWithTime("[SpotLock] Disengaged")
    }
    
    func jog(direction: JogDirection) {
        guard let currentLock = lockPosition else { return }
        
        let jogHeading: Double
        
        switch direction {
        case .forward:
            jogHeading = 0.0
        case .back:
            jogHeading = 180.0
        case .left:
            jogHeading = 270.0
        case .right:
            jogHeading = 90.0
        }
        
        let newPosition = calculateNewPosition(
            from: currentLock,
            heading: jogHeading,
            distance: jogDistanceMeters
        )
        
        lockPosition = newPosition
        positionHistory.removeAll()
        lastDistanceCheck = nil
        lastDistanceValue = 0
        
        let compassDirection: String
        switch direction {
        case .forward: compassDirection = "North"
        case .back: compassDirection = "South"
        case .left: compassDirection = "West"
        case .right: compassDirection = "East"
        }
        
        logWithTime("[SpotLock] Jogged \(compassDirection) to \(String(format: "%.6f, %.6f", newPosition.latitude, newPosition.longitude))")
    }
    
    func update() async {
        guard isActive else { return }
        guard let lockPos = lockPosition else { return }
        guard let sensors = bluetooth.sensorData else { return }
        
        guard sensors.hasFix && sensors.satellites >= 4 && sensors.hdop < 5.0 else {
            logWithTime("[SpotLock] GPS quality insufficient - disengaging")
            await disengage()
            return
        }
        
        updateSpeedHistory(sensors.speedKmh)
        
        let currentLocation = sensors.currentLocation
        let filteredLocation = applyLowPassFilter(currentLocation)
        
        let locationForDistance = positionHistory.count >= 3 ? filteredLocation : currentLocation
        distanceFromLock = locationForDistance.distance(to: lockPos)
        
        checkProgress()
        
        guard canSendCorrection() else { return }
        
        if isApplyingThrust {
            if distanceFromLock < (activationThresholdMeters * hysteresisRatio) {
                await stopThrust()
            } else {
                await applyCorrection(
                    from: filteredLocation,
                    to: lockPos,
                    currentHeading: sensors.heading
                )
            }
        } else {
            if distanceFromLock > activationThresholdMeters {
                await startThrust()
                await applyCorrection(
                    from: filteredLocation,
                    to: lockPos,
                    currentHeading: sensors.heading
                )
            }
        }
    }
    
    private func ensureMotorReady() async {
        logWithTime("[SpotLock] Ensuring motor speed is 0 - sending 10x RF_DOWN")
        
        motorState = .unknown
        for _ in 1...10 {
            bluetooth.sendCommand("RF_DOWN")
            try? await Task.sleep(for: .seconds(0.5))
        }
        
        motorState = .motorOff
        currentSpeedLevel = 0
        await turnMotorOn()
        logWithTime("[SpotLock] Assuming Motor is ON. Motor ready at speed 0")
    }
    
    private func startThrust() async {
        guard !isApplyingThrust else { return }
        guard !isMotorOperationInProgress else {
            logWithTime("[SpotLock] Motor operation in progress - skipping startThrust")
            return
        }

        await turnMotorOn()
        
        guard motorState == .motorOn else {
            logWithTime("[SpotLock] ERROR: Motor failed to turn ON")
            return
        }
        
        isApplyingThrust = true
        
        if currentSpeedLevel < minCorrectionSpeed {
            await setSpeed(minCorrectionSpeed)
        }
        
        logWithTime("[SpotLock] Thrust START (distance: \(String(format: "%.2f", distanceFromLock))m, speed: \(currentSpeedLevel))")
    }
    
    private func stopThrust() async {
        guard isApplyingThrust else { return }
        
        logWithTime("[SpotLock] Thrust STOP (within hysteresis: \(String(format: "%.2f", distanceFromLock))m)")
        
        await turnMotorOff()
        
        guard motorState == .motorOff else {
            logWithTime("[SpotLock] ERROR: Motor failed to turn ON")
            return
        }

        if lastSteeringDirection != .none {
            await releaseSteering()
        }
        
        await setSpeed(0)
        
        isApplyingThrust = false
    }
    
    private func turnMotorOn() async {
        guard !isMotorOperationInProgress else {
            logWithTime("[SpotLock] Motor operation already in progress")
            return
        }
        
        isMotorOperationInProgress = true
        
        if motorState == .motorOn {
            logWithTime("[SpotLock] Motor already ON")
        } else {
            logWithTime("[SpotLock] Sending RF_MOTOR to turn ON")
            bluetooth.sendCommand("RF_MOTOR")
            motorState = .motorOn
        }
        
        isMotorOperationInProgress = false
    }
    
    private func turnMotorOff() async {
        guard motorState == .motorOn else { return }
        guard !isMotorOperationInProgress else { return }
        
        isMotorOperationInProgress = true
        
        if motorState == .motorOff {
            logWithTime("[SpotLock] Motor already OFF")
        } else {
            logWithTime("[SpotLock] Sending RF_MOTOR to turn OFF")
            bluetooth.sendCommand("RF_MOTOR")
            motorState = .motorOff
        }
        
        if currentSpeedLevel > 0 {
            await setSpeed(0)
            currentSpeedLevel = 0
        }
        
        isMotorOperationInProgress = false
    }
    
    private func setSpeed(_ targetLevel: Int) async {
        let clampedTarget = min(max(targetLevel, 0), maxCorrectionSpeed)
        guard clampedTarget != currentSpeedLevel else { return }
        
        logWithTime("[SpotLock] Speed change: \(currentSpeedLevel) -> \(clampedTarget)")
        
        if clampedTarget > currentSpeedLevel {
            for _ in currentSpeedLevel..<clampedTarget {
                bluetooth.sendCommand("RF_UP")
                currentSpeedLevel += 1
                try? await Task.sleep(for: .seconds(speedChangeDelaySeconds))
            }
        } else {
            for _ in clampedTarget..<currentSpeedLevel {
                bluetooth.sendCommand("RF_DOWN")
                currentSpeedLevel -= 1
                try? await Task.sleep(for: .seconds(speedChangeDelaySeconds))
            }
        }
        
        logWithTime("[SpotLock] Speed set to level \(clampedTarget)")
    }
    
    private func applyCorrection(
        from currentLocation: CLLocationCoordinate2D,
        to targetLocation: CLLocationCoordinate2D,
        currentHeading: Double
    ) async {
        currentCorrectionBearing = currentLocation.bearing(to: targetLocation)
        
        let relativeAngle = calculateRelativeAngle(
            currentHeading: currentHeading,
            targetBearing: currentCorrectionBearing
        )
        
        let needsSteering = abs(relativeAngle) > headingToleranceDegrees
        
        if needsSteering {
            let direction = determineSteeringDirection(relativeAngle)
            
            if lastSteeringDirection != .none && lastSteeringDirection != direction {
                await releaseSteering()
            }
            
            await steer(direction: direction, relativeAngle: relativeAngle)
        } else {
            if lastSteeringDirection != .none {
                await releaseSteering()
            }
            
            let distanceBeyondDeadZone = max(0, distanceFromLock - deadZoneRadiusMeters)
            let targetSpeed = calculateProportionalSpeed(distanceBeyondDeadZone)
            
            if targetSpeed != currentSpeedLevel {
                await setSpeed(targetSpeed)
            }
        }
        
        lastCorrectionTime = Date()
        
        logWithTime("[SpotLock] Correction - Distance: \(String(format: "%.2f", distanceFromLock))m, " +
            "Bearing: \(String(format: "%.1f", currentCorrectionBearing))°, " +
            "Heading: \(String(format: "%.1f", currentHeading))°, " +
            "Relative: \(String(format: "%.1f", relativeAngle))°, " +
            "Speed: \(currentSpeedLevel), " +
            "Steering: \(needsSteering ? (relativeAngle > 0 ? "RIGHT" : "LEFT") : "NONE")")
    }
    
    private func calculateProportionalSpeed(_ distanceBeyondDeadZone: Double) -> Int {
        guard distanceBeyondDeadZone > 0 else { return minCorrectionSpeed }
        
        let proportionalGain = 0.3
        let rawSpeed = distanceBeyondDeadZone * proportionalGain + Double(minCorrectionSpeed)
        let clampedSpeed = min(rawSpeed, Double(maxCorrectionSpeed))
        
        return max(minCorrectionSpeed, Int(round(clampedSpeed)))
    }

    private func calculateSteeringDuration(for relativeAngle: Double) -> Int {
        let absAngle = abs(relativeAngle)
        
        if absAngle >= largeAngleThreshold {
            let ratio = min((absAngle - largeAngleThreshold) / (180.0 - largeAngleThreshold), 1.0)
            let duration = Int(1200 + ratio * 300)
            logWithTime("[SpotLock] Large angle \(String(format: "%.1f", absAngle))° → \(duration)ms press")
            return duration
        }
        
        if absAngle >= mediumAngleThreshold {
            let ratio = (absAngle - mediumAngleThreshold) / (largeAngleThreshold - mediumAngleThreshold)
            let duration = Int(700 + ratio * 500)
            logWithTime("[SpotLock] Medium angle \(String(format: "%.1f", absAngle))° → \(duration)ms press")
            return duration
        }
        
        let ratio = absAngle / mediumAngleThreshold
        let duration = Int(Double(minSteeringDurationMs) + ratio * 200)
        logWithTime("[SpotLock] Small angle \(String(format: "%.1f", absAngle))° → \(duration)ms press")
        return duration
    }
    
    private func steer(direction: SteeringDirection, relativeAngle: Double) async {
        guard direction != .none else { return }
        
        let command: String
        switch direction {
        case .left:
            command = "RF_LEFT_HOLD"
        case .right:
            command = "RF_RIGHT_HOLD"
        case .none:
            return
        }
        
        let holdDuration = calculateSteeringDuration(for: relativeAngle)
        
        bluetooth.sendCommand(command)
        lastSteeringDirection = direction
        
        try? await Task.sleep(for: .milliseconds(holdDuration))
        
        await releaseSteering()
    }
    
    private func releaseSteering() async {
        guard lastSteeringDirection != .none else { return }
        
        bluetooth.sendCommand("RF_RELEASE")
        lastSteeringDirection = .none
        
        try? await Task.sleep(for: .milliseconds(200))
    }
    
    private func checkProgress() {
        let now = Date()
        
        if lastDistanceCheck == nil {
            lastDistanceCheck = now
            lastDistanceValue = distanceFromLock
            return
        }
        
        guard let lastCheck = lastDistanceCheck else { return }
        let timeSinceCheck = now.timeIntervalSince(lastCheck)
        
        if timeSinceCheck >= progressCheckIntervalSeconds {
            let distanceChange = distanceFromLock - lastDistanceValue
            
            if distanceChange > maxAcceptableDrift {
                logWithTime("[SpotLock] ⚠️ WARNING: Drifting away! Distance increased by \(String(format: "%.2f", distanceChange))m in \(String(format: "%.0f", timeSinceCheck))s")
                logWithTime("[SpotLock] Consider: 1) Motor may not be ON, 2) Speed too low for conditions, 3) Heading not aligned")
            } else if distanceChange < -2.0 {
                logWithTime("[SpotLock] ✓ Making progress: Distance decreased by \(String(format: "%.2f", -distanceChange))m")
            }
            
            lastDistanceCheck = now
            lastDistanceValue = distanceFromLock
        }
    }
    
    private func updateSpeedHistory(_ speedKmh: Double) {
        let now = Date()
        speedHistory.append(SpeedSample(speedKmh: speedKmh, timestamp: now))
        
        if speedHistory.count > speedHistorySize {
            speedHistory.removeFirst()
        }
    }
    
    private func getAverageSpeed() -> Double {
        guard speedHistory.count >= 3 else {
            return bluetooth.sensorData?.speedKmh ?? 0
        }
        
        let recentSpeeds = speedHistory.suffix(5)
        return recentSpeeds.reduce(0.0) { $0 + $1.speedKmh } / Double(recentSpeeds.count)
    }
    
    private func applyLowPassFilter(_ location: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let now = Date()
        positionHistory.append(FilteredPosition(coordinate: location, timestamp: now))
        
        if positionHistory.count > filterWindowSize {
            positionHistory.removeFirst()
        }
        
        if positionHistory.count < 3 {
            return location
        }
        
        let totalWeight = Double(positionHistory.count)
        var weightedLat = 0.0
        var weightedLon = 0.0
        
        for position in positionHistory {
            weightedLat += position.coordinate.latitude
            weightedLon += position.coordinate.longitude
        }
        
        return CLLocationCoordinate2D(
            latitude: weightedLat / totalWeight,
            longitude: weightedLon / totalWeight
        )
    }
    
    private func canSendCorrection() -> Bool {
        guard let lastTime = lastCorrectionTime else { return true }
        return Date().timeIntervalSince(lastTime) >= correctionIntervalSeconds
    }
    
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
    
    private func determineSteeringDirection(_ relativeAngle: Double) -> SteeringDirection {
        if relativeAngle > headingToleranceDegrees {
            return .right
        } else if relativeAngle < -headingToleranceDegrees {
            return .left
        }
        return .none
    }
    
    private func calculateNewPosition(
        from position: CLLocationCoordinate2D,
        heading: Double,
        distance: Double
    ) -> CLLocationCoordinate2D {
        let headingRad = heading * .pi / 180.0
        let metersPerDegLat = 111320.0
        
        let newLat = position.latitude + (distance / metersPerDegLat) * cos(headingRad)
        let newLon = position.longitude + (distance / (metersPerDegLat * cos(position.latitude * .pi / 180.0))) * sin(headingRad)
        
        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }
    
    private func normalizeHeading(_ heading: Double) -> Double {
        var normalized = heading
        while normalized >= 360.0 {
            normalized -= 360.0
        }
        while normalized < 0.0 {
            normalized += 360.0
        }
        return normalized
    }
    
    private func logWithTime(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}