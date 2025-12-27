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
    
    private let deadZoneRadiusMeters: Double = 2.0
    private let activationThresholdMeters: Double = 4.0
    private let hysteresisRatio: Double = 0.5
    private let jogDistanceMeters: Double = 1.5
    private let minCorrectionSpeed: Int = 1
    private let maxCorrectionSpeed: Int = 3
    private let headingToleranceDegrees: Double = 30.0
    
    private var positionHistory: [FilteredPosition] = []
    private let filterWindowSize: Int = 5
    private var lastCorrectionTime: Date?
    private let correctionIntervalSeconds: Double = 2.0
    
    private var speedHistory: [SpeedSample] = []
    private let speedHistorySize: Int = 10
    private let initialMotorValidationDelaySeconds: Double = 3.0
    private let speedChangeDelaySeconds: Double = 1.5
    private let movementThresholdKmh: Double = 2.0 // to account for GPS drift
    
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
        
        logWithTime("[SpotLock] Engaged at \(String(format: "%.6f, %.6f", position.latitude, position.longitude))")
        logWithTime("[SpotLock] Dead zone: \(deadZoneRadiusMeters)m, Activation: \(activationThresholdMeters)m, Hysteresis: \(activationThresholdMeters * hysteresisRatio)m")
        
        await ensureMotorReady()
    }
    
    func disengage() async {
        guard isActive else { return }
        
        logWithTime("[SpotLock] Disengaging...")
        
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
        logWithTime("[SpotLock] Clearing motor state - sending 10x RF_DOWN")
        
        for _ in 1...10 {
            bluetooth.sendMotorCommand("RF_DOWN")
            try? await Task.sleep(for: .seconds(0.8))
        }
        
        currentSpeedLevel = 0
        motorState = .motorOff
        logWithTime("[SpotLock] Motor ready at speed 0")
    }
    
    private func startThrust() async {
        guard !isApplyingThrust else { return }
        guard !isMotorOperationInProgress else {
            logWithTime("[SpotLock] Motor operation in progress - skipping startThrust")
            return
        }
        
        if motorState != .motorOn {
            logWithTime("[SpotLock] Turning motor ON")
            await turnMotorOn()
        }
        
        guard motorState == .motorOn else {
            logWithTime("[SpotLock] ERROR: Motor failed to turn ON")
            return
        }
        
        isApplyingThrust = true
        
        if currentSpeedLevel == 0 {
            await setSpeed(minCorrectionSpeed)
        }
        
        logWithTime("[SpotLock] Thrust START (distance: \(String(format: "%.2f", distanceFromLock))m, speed: \(currentSpeedLevel))")
    }
    
    private func stopThrust() async {
        guard isApplyingThrust else { return }
        
        logWithTime("[SpotLock] Thrust STOP (within hysteresis: \(String(format: "%.2f", distanceFromLock))m)")
        
        await setSpeed(0)
        
        isApplyingThrust = false
    }
    
    private func turnMotorOn() async {
        guard !isMotorOperationInProgress else {
            logWithTime("[SpotLock] Motor operation already in progress")
            return
        }
        
        isMotorOperationInProgress = true
        motorState = .validating
        
        logWithTime("[SpotLock] Validating motor state - ramping speed to detect if motor is ON")
        
        // Ramp speed to level 2 to detect if motor is already running
        let targetValidationLevel = 2
        while currentSpeedLevel < targetValidationLevel {
            bluetooth.sendMotorCommand("RF_UP")
            currentSpeedLevel += 1
            try? await Task.sleep(for: .seconds(speedChangeDelaySeconds))
        }
        
        logWithTime("[SpotLock] Speed at level \(currentSpeedLevel) - checking for movement")
        try? await Task.sleep(for: .seconds(initialMotorValidationDelaySeconds))
        
        let speedAfterRamp = getAverageSpeed()
        
        if speedAfterRamp > movementThresholdKmh {
            logWithTime("[SpotLock] Motor already ON - detected movement (speed: \(String(format: "%.2f", speedAfterRamp)) km/h)")
            motorState = .motorOn
            isMotorOperationInProgress = false
            return
        }
        
        logWithTime("[SpotLock] No movement detected - toggling RF_MOTOR to turn ON")
        bluetooth.sendMotorCommand("RF_MOTOR")
        
        try? await Task.sleep(for: .seconds(initialMotorValidationDelaySeconds))
        
        let speedAfterToggle = getAverageSpeed()
        
        if speedAfterToggle > movementThresholdKmh {
            logWithTime("[SpotLock] Motor confirmed ON (speed: \(String(format: "%.2f", speedAfterToggle)) km/h)")
            motorState = .motorOn
        } else {
            logWithTime("[SpotLock] WARNING: No movement detected after motor toggle (speed: \(String(format: "%.2f", speedAfterToggle)) km/h)")
            logWithTime("[SpotLock] Assuming motor is ON - may be stationary or GPS speed not updating")
            motorState = .motorOn
        }
        
        isMotorOperationInProgress = false
    }
    
    private func turnMotorOff() async {
        guard motorState == .motorOn else { return }
        guard !isMotorOperationInProgress else { return }
        
        isMotorOperationInProgress = true
        
        if currentSpeedLevel > 0 {
            await setSpeed(0)
        }
        
        logWithTime("[SpotLock] Sending RF_MOTOR to turn OFF")
        bluetooth.sendMotorCommand("RF_MOTOR")
        motorState = .motorOff
        currentSpeedLevel = 0
        
        isMotorOperationInProgress = false
    }
    
    private func setSpeed(_ targetLevel: Int) async {
        let clampedTarget = min(max(targetLevel, 0), maxCorrectionSpeed)
        guard clampedTarget != currentSpeedLevel else { return }
        
        logWithTime("[SpotLock] Speed change: \(currentSpeedLevel) -> \(clampedTarget)")
        
        if clampedTarget > currentSpeedLevel {
            for _ in currentSpeedLevel..<clampedTarget {
                bluetooth.sendMotorCommand("RF_UP")
                currentSpeedLevel += 1
                try? await Task.sleep(for: .seconds(speedChangeDelaySeconds))
            }
        } else {
            for _ in clampedTarget..<currentSpeedLevel {
                bluetooth.sendMotorCommand("RF_DOWN")
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
            await steer(direction: direction)
        }
        
        let distanceBeyondDeadZone = max(0, distanceFromLock - deadZoneRadiusMeters)
        let targetSpeed = calculateProportionalSpeed(distanceBeyondDeadZone)
        
        if targetSpeed != currentSpeedLevel && targetSpeed <= maxCorrectionSpeed {
            await setSpeed(targetSpeed)
        }
        
        lastCorrectionTime = Date()
        
        logWithTime("[SpotLock] Correction - Distance: \(String(format: "%.2f", distanceFromLock))m, " +
              "Bearing: \(String(format: "%.1f", currentCorrectionBearing))°, " +
              "Relative: \(String(format: "%.1f", relativeAngle))°, " +
              "Speed: \(currentSpeedLevel), " +
              "Steering: \(needsSteering ? (relativeAngle > 0 ? "RIGHT" : "LEFT") : "NONE")")
    }
    
    private func calculateProportionalSpeed(_ distanceBeyondDeadZone: Double) -> Int {
        guard distanceBeyondDeadZone > 0 else { return minCorrectionSpeed }
        
        let proportionalGain = 0.5
        let rawSpeed = distanceBeyondDeadZone * proportionalGain
        let clampedSpeed = min(rawSpeed, Double(maxCorrectionSpeed))
        
        return max(minCorrectionSpeed, Int(round(clampedSpeed)))
    }
    
    private func steer(direction: SteeringDirection) async {
        switch direction {
        case .left:
            bluetooth.sendMotorCommand("RF_LEFT")
        case .right:
            bluetooth.sendMotorCommand("RF_RIGHT")
        case .none:
            break
        }
        
        try? await Task.sleep(for: .milliseconds(100))
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