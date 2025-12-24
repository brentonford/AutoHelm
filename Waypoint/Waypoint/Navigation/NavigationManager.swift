import Foundation
import CoreLocation
import Combine

@MainActor
class NavigationManager: ObservableObject {
    
    @Published private(set) var state: NavigationState = .idle
    @Published private(set) var currentPhase: NavigationPhase = .idle
    @Published private(set) var steeringCommand: String = "None"
    @Published private(set) var speedCommand: String = "Stopped"
    
    let motorController: MotorController
    let speedController: SpeedController
    let steeringController: SteeringController
    let spotLockController: SpotLockController
    
    private var navigationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init(bluetoothManager: BluetoothManager) {
        self.motorController = MotorController(bluetooth: bluetoothManager)
        self.speedController = SpeedController(bluetooth: bluetoothManager)
        self.steeringController = SteeringController(bluetooth: bluetoothManager)
        self.spotLockController = SpotLockController(bluetooth: bluetoothManager)
        
        setupBindings()
    }
    
    private func setupBindings() {
        motorController.$currentSpeedLevel
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        speedController.$speedCommand
            .assign(to: &$speedCommand)
        
        steeringController.$steeringCommand
            .assign(to: &$steeringCommand)
    }
    
    func startNavigation(to waypoint: Waypoint, from currentLocation: CLLocationCoordinate2D) async throws {
        guard state == .idle else {
            throw NavigationError.alreadyNavigating
        }
        
        state = .navigating(waypoint: waypoint)
        currentPhase = .initializing
        
        do {
            try await motorController.initialize()
            
            currentPhase = .navigating
            let targetSpeed = waypoint.approachSpeed > 0 ? waypoint.approachSpeed : 3.6
            speedController.setTargetSpeed(targetSpeed)
            
            startNavigationLoop()
            
        } catch {
            state = .idle
            throw NavigationError.motorInitializationFailed
        }
    }
    
    func stopNavigation() async {
        navigationTimer?.invalidate()
        navigationTimer = nil
        
        currentPhase = .stopping
        await motorController.shutdown()
        
        state = .idle
        currentPhase = .idle
    }
    
    func engageSpotLock(at position: CLLocationCoordinate2D) {
        state = .spotLock(position: position)
        currentPhase = .spotLock
        spotLockController.engage(at: position)
        startSpotLockLoop()
    }
    
    func disengageSpotLock() async {
        await spotLockController.disengage()
        state = .idle
        currentPhase = .idle
    }
    
    private func startNavigationLoop() {
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.executeNavigationCycle()
            }
        }
    }
    
    private func startSpotLockLoop() {
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.spotLockController.update()
            }
        }
    }
    
    private func executeNavigationCycle() async {
        guard case .navigating(let waypoint) = state else { return }
        
        let sensors = motorController.sensorData
        guard let currentLocation = sensors?.currentLocation else { return }
        
        let distance = currentLocation.distance(to: waypoint.coordinate)
        if distance <= waypoint.arrivalRadius {
            currentPhase = .arrived
            
            if waypoint.spotLockEnabled {
                engageSpotLock(at: waypoint.coordinate)
            } else {
                await stopNavigation()
            }
            return
        }
        
        await steeringController.updateSteering(
            from: currentLocation,
            to: waypoint.coordinate,
            currentHeading: sensors?.heading ?? 0
        )
        
        await speedController.updateSpeed(
            currentSpeed: sensors?.speedKmh ?? 0
        )
    }
}

enum NavigationState: Equatable {
    case idle
    case navigating(waypoint: Waypoint)
    case spotLock(position: CLLocationCoordinate2D)
    case error(NavigationError)
}

enum NavigationPhase {
    case idle
    case initializing
    case clearingPower
    case verifyingMotor
    case navigating
    case accelerating
    case cruising
    case maintaining
    case spotLock
    case arrived
    case stopping
}

enum NavigationError: Error {
    case alreadyNavigating
    case motorInitializationFailed
    case motorNotResponding
    case gpsSignalLost
}