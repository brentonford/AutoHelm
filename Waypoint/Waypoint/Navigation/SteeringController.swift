import Foundation
import CoreLocation
import Combine

@MainActor
class SteeringController: ObservableObject {
    
    @Published private(set) var steeringCommand: String = "None"
    @Published private(set) var currentBearing: Double = 0
    @Published private(set) var relativeAngle: Double = 0
    
    private let bluetooth: BluetoothManager
    private let motorController: MotorController
    
    private var lastSteeringCommandTime: Date?
    private let steeringIntervalSeconds: Double = 2.0
    private let headingToleranceDegrees: Double = 15.0
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        self.motorController = MotorController(bluetooth: bluetooth)
    }
    
    func updateSteering(
        from currentLocation: CLLocationCoordinate2D,
        to targetLocation: CLLocationCoordinate2D,
        currentHeading: Double
    ) async {
        currentBearing = currentLocation.bearing(to: targetLocation)
        relativeAngle = calculateRelativeAngle(
            currentHeading: currentHeading,
            targetBearing: currentBearing
        )
        
        guard needsSteeringCorrection() else {
            steeringCommand = "On Course"
            return
        }
        
        guard canSendSteeringCommand() else {
            return
        }
        
        let direction = determineSteeringDirection()
        await motorController.sendSteeringCommand(direction)
        
        switch direction {
        case .left:
            steeringCommand = "LEFT"
        case .right:
            steeringCommand = "RIGHT"
        case .none:
            steeringCommand = "On Course"
        }
        
        lastSteeringCommandTime = Date()
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
    
    private func needsSteeringCorrection() -> Bool {
        abs(relativeAngle) > headingToleranceDegrees
    }
    
    private func determineSteeringDirection() -> SteeringDirection {
        if relativeAngle > headingToleranceDegrees {
            return .right
        } else if relativeAngle < -headingToleranceDegrees {
            return .left
        }
        return .none
    }
    
    private func canSendSteeringCommand() -> Bool {
        guard let lastTime = lastSteeringCommandTime else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= steeringIntervalSeconds
    }
}