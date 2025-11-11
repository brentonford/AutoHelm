import Foundation
import CoreLocation
import Combine

@MainActor
class NavigationDataManager: ObservableObject {
    @Published var currentNavigationState: AppNavigationState = .idle
    @Published var distanceToTarget: CLLocationDistance = 0
    @Published var bearingToTarget: CLLocationDirection = 0
    @Published var isNavigating: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let navigationStateSubject = PassthroughSubject<AppNavigationState, Never>()
    
    // Dependencies
    private let locationManager: LocationManager
    private let bluetoothManager: BluetoothManager
    
    // Publishers for reactive navigation data
    var navigationStatePublisher: AnyPublisher<AppNavigationState, Never> {
        navigationStateSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    var distancePublisher: AnyPublisher<CLLocationDistance, Never> {
        $distanceToTarget
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates { abs($0 - $1) < 1.0 }
            .eraseToAnyPublisher()
    }
    
    var bearingPublisher: AnyPublisher<CLLocationDirection, Never> {
        $bearingToTarget
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates { abs($0 - $1) < 1.0 }
            .eraseToAnyPublisher()
    }
    
    // Combined navigation data stream
    var navigationDataPublisher: AnyPublisher<NavigationData, Never> {
        Publishers.CombineLatest4(
            navigationStatePublisher,
            distancePublisher,
            bearingPublisher,
            locationManager.coordinatePublisher
        )
        .map { state, distance, bearing, coordinate in
            NavigationData(
                state: state,
                distance: distance,
                bearing: bearing,
                currentLocation: coordinate
            )
        }
        .eraseToAnyPublisher()
    }
    
    init(locationManager: LocationManager, bluetoothManager: BluetoothManager) {
        self.locationManager = locationManager
        self.bluetoothManager = bluetoothManager
        setupReactiveNavigationPipeline()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupReactiveNavigationPipeline() {
        // Navigation state updates
        navigationStateSubject
            .removeDuplicates()
            .sink { [weak self] state in
                self?.currentNavigationState = state
                self?.isNavigating = state != .idle
            }
            .store(in: &cancellables)
        
        // Combine location updates with device status for navigation calculations
        Publishers.CombineLatest(
            locationManager.highAccuracyLocationPublisher,
            bluetoothManager.deviceStatusPublisher
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] location, deviceStatus in
            self?.updateNavigationData(currentLocation: location, deviceStatus: deviceStatus)
        }
        .store(in: &cancellables)
        
        // Device status changes affect navigation state
        bluetoothManager.deviceStatusPublisher
            .map { $0.hasGpsFix }
            .removeDuplicates()
            .sink { [weak self] hasGpsFix in
                if !hasGpsFix && self?.isNavigating == true {
                    self?.navigationStateSubject.send(.error("GPS fix lost"))
                }
            }
            .store(in: &cancellables)
        
        // Connection state affects navigation
        bluetoothManager.connectionStatePublisher
            .filter { !$0 } // When disconnected
            .sink { [weak self] _ in
                if self?.isNavigating == true {
                    self?.navigationStateSubject.send(.error("Device disconnected"))
                }
            }
            .store(in: &cancellables)
        
        // Auto-update navigation every second when navigating
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .filter { [weak self] _ in self?.isNavigating == true }
            .combineLatest(locationManager.locationPublisher)
            .sink { [weak self] _, location in
                self?.updateNavigationCalculations(from: location)
            }
            .store(in: &cancellables)
        
        // Arrival detection
        distancePublisher
            .filter { $0 <= SystemConfig.waypointArrivalDistance }
            .combineLatest(navigationStatePublisher)
            .filter { _, state in state == .navigating }
            .sink { [weak self] _, _ in
                self?.navigationStateSubject.send(.arrived)
            }
            .store(in: &cancellables)
    }
    
    func startNavigation(to coordinate: CLLocationCoordinate2D) {
        guard bluetoothManager.isConnected else {
            navigationStateSubject.send(.error("Device not connected"))
            return
        }
        
        bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        navigationStateSubject.send(.navigating)
    }
    
    func stopNavigation() {
        bluetoothManager.disableNavigation()
        navigationStateSubject.send(.idle)
        distanceToTarget = 0
        bearingToTarget = 0
    }
    
    private func updateNavigationData(currentLocation: CLLocation, deviceStatus: DeviceStatus) {
        guard let targetCoordinate = deviceStatus.targetCoordinate else { return }
        
        let targetLocation = CLLocation(latitude: targetCoordinate.latitude,
                                      longitude: targetCoordinate.longitude)
        
        distanceToTarget = currentLocation.distance(from: targetLocation)
        bearingToTarget = calculateBearing(from: currentLocation.coordinate,
                                         to: targetCoordinate)
    }
    
    private func updateNavigationCalculations(from location: CLLocation) {
        guard let deviceStatus = bluetoothManager.deviceStatus,
              let targetCoordinate = deviceStatus.targetCoordinate else { return }
        
        let targetLocation = CLLocation(latitude: targetCoordinate.latitude,
                                      longitude: targetCoordinate.longitude)
        
        let newDistance = location.distance(from: targetLocation)
        let newBearing = calculateBearing(from: location.coordinate, to: targetCoordinate)
        
        distanceToTarget = newDistance
        bearingToTarget = newBearing
    }
    
    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        
        let x = sin(deltaLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        let bearing = atan2(x, y) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }
}

// MARK: - Supporting Data Models
struct NavigationData {
    let state: AppNavigationState
    let distance: CLLocationDistance
    let bearing: CLLocationDirection
    let currentLocation: CLLocationCoordinate2D
}