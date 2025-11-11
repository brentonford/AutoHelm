import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationServicesEnabled: Bool = false
    @Published var locationAccuracy: CLLocationAccuracy = 0.0
    @Published var lastKnownLocation: CLLocation?
    @Published var locationError: String?
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Combine subjects for reactive data streams
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let authorizationSubject = PassthroughSubject<CLAuthorizationStatus, Never>()
    private let errorSubject = PassthroughSubject<String, Never>()
    
    // Public publishers for external consumption
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject
            .debounce(for: .milliseconds(1000), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    var coordinatePublisher: AnyPublisher<CLLocationCoordinate2D, Never> {
        locationPublisher
            .map { $0.coordinate }
            .removeDuplicates { previous, current in
                abs(previous.latitude - current.latitude) < 0.000001 &&
                abs(previous.longitude - current.longitude) < 0.000001
            }
            .eraseToAnyPublisher()
    }
    
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    var errorPublisher: AnyPublisher<String, Never> {
        errorSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    // Reactive location accuracy stream
    var accuracyPublisher: AnyPublisher<CLLocationAccuracy, Never> {
        locationPublisher
            .map { $0.horizontalAccuracy }
            .removeDuplicates { abs($0 - $1) < 1.0 }
            .eraseToAnyPublisher()
    }
    
    // High-accuracy location stream (accuracy < 10m)
    var highAccuracyLocationPublisher: AnyPublisher<CLLocation, Never> {
        locationPublisher
            .filter { $0.horizontalAccuracy < 10.0 && $0.horizontalAccuracy > 0 }
            .eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        setupLocationManager()
        setupReactiveDataPipeline()
        // Initialize location services check asynchronously
        Task {
            await initializeLocationServices()
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupReactiveDataPipeline() {
        // Debounced location updates
        locationSubject
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] location in
                self?.userLocation = location.coordinate
                self?.lastKnownLocation = location
                self?.locationAccuracy = location.horizontalAccuracy
                self?.locationError = nil
            }
            .store(in: &cancellables)
        
        // Authorization status updates - wait for delegate callback instead of polling
        authorizationSubject
            .removeDuplicates()
            .sink { [weak self] status in
                self?.authorizationStatus = status
                self?.handleAuthorizationChange(status)
            }
            .store(in: &cancellables)
        
        // Error handling with debouncing
        errorSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] error in
                self?.locationError = error
            }
            .store(in: &cancellables)
        
        // Automatic location updates when authorized - use delegate callback
        authorizationPublisher
            .filter { $0 == .authorizedWhenInUse || $0 == .authorizedAlways }
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.startLocationUpdatesAsync()
                }
            }
            .store(in: &cancellables)
        
        // Location timeout handling
        locationSubject
            .flatMap { _ in
                Timer.publish(every: 30.0, on: .main, in: .common)
                    .autoconnect()
                    .prefix(1)
            }
            .sink { [weak self] _ in
                if let lastLocation = self?.lastKnownLocation,
                   Date().timeIntervalSince(lastLocation.timestamp) > 30.0 {
                    self?.errorSubject.send("Location updates may be stale")
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        // Get initial authorization status synchronously (this is safe and recommended)
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // ASYNC/AWAIT PATTERN: Non-blocking initialization
    private func initializeLocationServices() async {
        // Move location services check off main thread
        let servicesEnabled = await Task.detached {
            CLLocationManager.locationServicesEnabled()
        }.value
        
        await MainActor.run { [weak self] in
            self?.isLocationServicesEnabled = servicesEnabled
        }
    }
    
    func requestPermission() {
        Task {
            await requestPermissionAsync()
        }
    }
    
    // BEST PRACTICE: Async permission handling without blocking main thread
    private func requestPermissionAsync() async {
        // Check location services availability asynchronously
        let servicesEnabled = await Task.detached {
            CLLocationManager.locationServicesEnabled()
        }.value
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            
            self.isLocationServicesEnabled = servicesEnabled
            
            guard servicesEnabled else {
                self.errorSubject.send("Location services are disabled. Please enable them in Settings.")
                return
            }
            
            // Use current authorization status (already available synchronously)
            switch self.authorizationStatus {
            case .notDetermined:
                // This is safe and non-blocking - delegate will handle response
                self.locationManager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                self.errorSubject.send("Location access denied. Please grant permission in Settings.")
            case .authorizedWhenInUse, .authorizedAlways:
                Task { @MainActor in
                    await self.startLocationUpdatesAsync()
                }
            @unknown default:
                self.errorSubject.send("Unknown location authorization status.")
            }
        }
    }
    
    // ASYNC PATTERN: Non-blocking location updates
    private func startLocationUpdatesAsync() async {
        // Double-check authorization without blocking
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            errorSubject.send("Location permission not granted.")
            return
        }
        
        guard isLocationServicesEnabled else {
            errorSubject.send("Location services are not enabled.")
            return
        }
        
        // This is the safe, non-blocking way to start location updates
        locationManager.startUpdatingLocation()
    }
    
    func startUpdatingLocation() {
        Task { @MainActor in
            await startLocationUpdatesAsync()
        }
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    func getCurrentLocationCoordinate() -> CLLocationCoordinate2D? {
        return userLocation
    }
    
    func getDistanceFromCurrentLocation(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let currentLocation = lastKnownLocation else { return nil }
        
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return currentLocation.distance(from: targetLocation)
    }
    
    func getBearingFromCurrentLocation(to coordinate: CLLocationCoordinate2D) -> CLLocationDirection? {
        guard let currentLocation = lastKnownLocation else { return nil }
        
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        let lat1 = currentLocation.coordinate.latitude * .pi / 180
        let lat2 = targetLocation.coordinate.latitude * .pi / 180
        let deltaLon = (targetLocation.coordinate.longitude - currentLocation.coordinate.longitude) * .pi / 180
        
        let x = sin(deltaLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        let bearing = atan2(x, y) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }
    
    // DELEGATE CALLBACK PATTERN: React to authorization changes instead of polling
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        // Update location services availability when authorization changes
        Task {
            let servicesEnabled = await Task.detached {
                CLLocationManager.locationServicesEnabled()
            }.value
            
            await MainActor.run { [weak self] in
                self?.isLocationServicesEnabled = servicesEnabled
            }
        }
        
        switch status {
        case .notDetermined:
            locationError = nil
        case .denied, .restricted:
            userLocation = nil
            lastKnownLocation = nil
            stopUpdatingLocation()
            errorSubject.send("Location access denied. Please grant permission in Settings.")
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
            Task { @MainActor in
                await startLocationUpdatesAsync()
            }
        @unknown default:
            errorSubject.send("Unknown location authorization status.")
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.locationSubject.send(location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.authorizationSubject.send(.denied)
                    self.errorSubject.send("Location access denied.")
                case .locationUnknown:
                    self.errorSubject.send("Unable to determine location.")
                case .network:
                    self.errorSubject.send("Network error occurred while fetching location.")
                default:
                    self.errorSubject.send(clError.localizedDescription)
                }
            } else {
                self.errorSubject.send(error.localizedDescription)
            }
        }
    }
    
    // KEY FIX: Use delegate callback instead of polling authorization status
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationSubject.send(status)
        }
    }
}