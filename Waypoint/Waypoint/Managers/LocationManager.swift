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
    
    override init() {
        super.init()
        setupLocationManager()
        checkLocationServices()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        authorizationStatus = locationManager.authorizationStatus
    }
    
    private func checkLocationServices() {
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
    }
    
    func requestPermission() {
        checkLocationServices()
        
        guard isLocationServicesEnabled else {
            locationError = "Location services are disabled. Please enable them in Settings."
            return
        }
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationError = "Location access denied. Please grant permission in Settings."
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        @unknown default:
            locationError = "Unknown location authorization status."
        }
    }
    
    func startUpdatingLocation() {
        guard isLocationServicesEnabled else {
            locationError = "Location services are not enabled."
            return
        }
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            locationError = "Location permission not granted."
            return
        }
        
        locationError = nil
        locationManager.startUpdatingLocation()
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
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.userLocation = location.coordinate
            self.lastKnownLocation = location
            self.locationAccuracy = location.horizontalAccuracy
            self.locationError = nil
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.authorizationStatus = .denied
                    self.locationError = "Location access denied."
                case .locationUnknown:
                    self.locationError = "Unable to determine location."
                case .network:
                    self.locationError = "Network error occurred while fetching location."
                default:
                    self.locationError = clError.localizedDescription
                }
            } else {
                self.locationError = error.localizedDescription
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            
            switch status {
            case .notDetermined:
                self.locationError = nil
            case .denied, .restricted:
                self.userLocation = nil
                self.lastKnownLocation = nil
                self.stopUpdatingLocation()
                self.locationError = "Location access denied. Please grant permission in Settings."
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationError = nil
                self.startUpdatingLocation()
            @unknown default:
                self.locationError = "Unknown location authorization status."
            }
        }
    }
}