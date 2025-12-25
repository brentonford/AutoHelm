import Foundation
import CoreLocation
import Combine

@MainActor
class SpotLockController: ObservableObject {
    
    @Published private(set) var lockPosition: CLLocationCoordinate2D?
    @Published private(set) var isActive: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    @Published private(set) var isApplyingThrust: Bool = false
    @Published private(set) var currentCorrectionBearing: Double = 0
    
    private let bluetooth: BluetoothManager
    private let motorController: MotorController
    private let steeringController: SteeringController
    
    private let deadZoneRadiusMeters: Double = 1.5
    private let activationThresholdMeters: Double = 2.0
    private let hysteresisRatio: Double = 0.5
    private let jogDistanceMeters: Double = 1.5
    private let maxCorrectionSpeedLevel: Int = 3
    private let headingToleranceDegrees: Double = 30.0
    
    private var positionHistory: [FilteredPosition] = []
    private let filterWindowSize: Int = 5
    private var lastCorrectionTime: Date?
    private let correctionIntervalSeconds: Double = 2.0
    
    private struct FilteredPosition {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        self.motorController = MotorController(bluetooth: bluetooth)
        self.steeringController = SteeringController(bluetooth: bluetooth)
    }
    
    func engage(at position: CLLocationCoordinate2D) {
        lockPosition = position
        isActive = true
        isApplyingThrust = false
        distanceFromLock = 0
        positionHistory.removeAll()
        lastCorrectionTime = nil
        
        print("[SpotLock] Engaged at \(String(format: "%.6f, %.6f", position.latitude, position.longitude))")
        print("[SpotLock] Dead zone: \(deadZoneRadiusMeters)m, Activation threshold: \(activationThresholdMeters)m")
    }
    
    func disengage() async {
        guard isActive else { return }
        
        if isApplyingThrust {
            bluetooth.sendMotorCommand("RF_RELEASE")
            isApplyingThrust = false
        }
        
        isActive = false
        lockPosition = nil
        distanceFromLock = 0
        positionHistory.removeAll()
        lastCorrectionTime = nil
        
        print("[SpotLock] Disengaged")
    }
    
    func jog(direction: JogDirection, currentHeading: Double) {
        guard let currentLock = lockPosition else { return }
        
        var jogHeading = currentHeading
        
        switch direction {
        case .forward:
            break
        case .back:
            jogHeading += 180.0
        case .left:
            jogHeading -= 90.0
        case .right:
            jogHeading += 90.0
        }
        
        jogHeading = normalizeHeading(jogHeading)
        
        let newPosition = calculateNewPosition(
            from: currentLock,
            heading: jogHeading,
            distance: jogDistanceMeters
        )
        
        lockPosition = newPosition
        positionHistory.removeAll()
        
        print("[SpotLock] Jogged \(direction) to \(String(format: "%.6f, %.6f", newPosition.latitude, newPosition.longitude))")
    }
    
    func update() async {
        guard isActive else { return }
        guard let lockPos = lockPosition else { return }
        guard let sensors = bluetooth.sensorData else { return }
        
        guard sensors.hasFix && sensors.satellites >= 4 && sensors.hdop < 5.0 else {
            print("[SpotLock] GPS quality insufficient - disengaging")
            await disengage()
            return
        }
        
        let currentLocation = sensors.currentLocation
        let filteredLocation = applyLowPassFilter(currentLocation)
        
        distanceFromLock = filteredLocation.distance(to: lockPos)
        
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
    
    private func startThrust() async {
        guard !isApplyingThrust else { return }
        
        bluetooth.sendMotorCommand("RF_MOMENTARY_HOLD")
        isApplyingThrust = true
        
        print("[SpotLock] Thrust activated - distance: \(String(format: "%.2f", distanceFromLock))m")
    }
    
    private func stopThrust() async {
        guard isApplyingThrust else { return }
        
        bluetooth.sendMotorCommand("RF_RELEASE")
        isApplyingThrust = false
        
        print("[SpotLock] Thrust released - within dead zone: \(String(format: "%.2f", distanceFromLock))m")
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
            
            if abs(relativeAngle) > 90.0 {
                lastCorrectionTime = Date()
                print("[SpotLock] Large heading error (\(String(format: "%.1f", relativeAngle))°) - steering only")
                return
            }
        }
        
        let distanceBeyondDeadZone = distanceFromLock - deadZoneRadiusMeters
        let proportionalSpeed = calculateProportionalSpeed(distanceBeyondDeadZone)
        
        await adjustSpeed(targetLevel: proportionalSpeed)
        
        lastCorrectionTime = Date()
        
        print("[SpotLock] Correction applied - Distance: \(String(format: "%.2f", distanceFromLock))m, " +
              "Bearing: \(String(format: "%.1f", currentCorrectionBearing))°, " +
              "Relative: \(String(format: "%.1f", relativeAngle))°, " +
              "Speed: \(proportionalSpeed)")
    }
    
    private func calculateProportionalSpeed(_ distanceBeyondDeadZone: Double) -> Int {
        guard distanceBeyondDeadZone > 0 else { return 0 }
        
        let proportionalGain = 0.4
        let rawSpeed = distanceBeyondDeadZone * proportionalGain
        let clampedSpeed = min(rawSpeed, Double(maxCorrectionSpeedLevel))
        
        return max(1, Int(round(clampedSpeed)))
    }
    
    private func adjustSpeed(targetLevel: Int) async {
        let currentLevel = motorController.currentSpeedLevel
        
        if targetLevel > currentLevel {
            for _ in currentLevel..<targetLevel {
                await motorController.increaseSpeed()
                try? await Task.sleep(for: .milliseconds(500))
            }
        } else if targetLevel < currentLevel {
            for _ in targetLevel..<currentLevel {
                await motorController.decreaseSpeed()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    
    private func steer(direction: SteeringDirection) async {
        switch direction {
        case .left:
            bluetooth.sendMotorCommand("RF_LEFT")
            print("[SpotLock] Steering LEFT")
        case .right:
            bluetooth.sendMotorCommand("RF_RIGHT")
            print("[SpotLock] Steering RIGHT")
        case .none:
            break
        }
        
        try? await Task.sleep(for: .milliseconds(100))
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
}