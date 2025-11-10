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
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        authorizationStatus = locationManager.authorizationStatus
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
    }
    
    func requestPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            isLocationServicesEnabled = false
            return
        }
        
        isLocationServicesEnabled = true
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    func startUpdatingLocation() {
        guard CLLocationManager.locationServicesEnabled(),
              authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
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
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.userLocation = location.coordinate
            self.lastKnownLocation = location
            self.locationAccuracy = location.horizontalAccuracy
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        
        Task { @MainActor in
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.authorizationStatus = .denied
                case .locationUnknown:
                    break
                case .network:
                    print("Network error occurred while fetching location")
                default:
                    print("Other location error: \(clError.localizedDescription)")
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            
            switch status {
            case .notDetermined:
                break
            case .denied, .restricted:
                self.userLocation = nil
                self.lastKnownLocation = nil
                self.stopUpdatingLocation()
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            @unknown default:
                break
            }
        }
    }
}