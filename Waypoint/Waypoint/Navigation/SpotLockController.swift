import Foundation
import CoreLocation
import Combine

@MainActor
class SpotLockController: ObservableObject {
    
    @Published private(set) var lockPosition: CLLocationCoordinate2D?
    @Published private(set) var isHoldingMomentary: Bool = false
    @Published private(set) var distanceFromLock: Double = 0
    
    private let bluetooth: BluetoothManager
    private let motorController: MotorController
    private let steeringController: SteeringController
    
    private let holdRadiusMeters: Double = 2.0
    private let jogDistanceMeters: Double = 1.5
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        self.motorController = MotorController(bluetooth: bluetooth)
        self.steeringController = SteeringController(bluetooth: bluetooth)
    }
    
    func engage(at position: CLLocationCoordinate2D) {
        lockPosition = position
        isHoldingMomentary = false
    }
    
    func disengage() async {
        if isHoldingMomentary {
            await motorController.sendSteeringCommand(.none)
            bluetooth.sendMotorCommand("RF_RELEASE")
            isHoldingMomentary = false
        }
        lockPosition = nil
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
        
        jogHeading = ((jogHeading + 360).truncatingRemainder(dividingBy: 360))
        
        let newPosition = calculateNewPosition(
            from: currentLock,
            heading: jogHeading,
            distance: jogDistanceMeters
        )
        
        lockPosition = newPosition
    }
    
    func update() async {
        guard let lockPos = lockPosition else { return }
        guard let sensors = bluetooth.sensorData else { return }
        
        let currentLocation = sensors.currentLocation
        distanceFromLock = currentLocation.distance(to: lockPos)
        
        if distanceFromLock > holdRadiusMeters {
            if !isHoldingMomentary {
                bluetooth.sendMotorCommand("RF_MOMENTARY_HOLD")
                isHoldingMomentary = true
            }
            
            await steeringController.updateSteering(
                from: currentLocation,
                to: lockPos,
                currentHeading: sensors.heading
            )
            
        } else {
            if isHoldingMomentary {
                bluetooth.sendMotorCommand("RF_RELEASE")
                isHoldingMomentary = false
            }
        }
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
}