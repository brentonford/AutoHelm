import SwiftUI
import CoreLocation

class WaypointManager: ObservableObject {
    @Published var savedWaypoints: [Waypoint] = []
    
    init() {
        loadWaypoints()
    }
    
    func saveWaypoint(_ waypoint: Waypoint) {
        var savedWaypoint = waypoint
        savedWaypoint.isSaved = true
        savedWaypoint.lastUpdatedDate = Date()
        savedWaypoints.append(savedWaypoint)
        saveToStorage()
    }
    
    func updateWaypoint(id: UUID, name: String? = nil, comments: String? = nil, photoData: Data? = nil, iconName: String? = nil) {
        if let index = savedWaypoints.firstIndex(where: { $0.id == id }) {
            if let name = name {
                savedWaypoints[index].name = name
            }
            if let comments = comments {
                savedWaypoints[index].comments = comments
            }
            if let photoData = photoData {
                savedWaypoints[index].photoData = photoData
            }
            if let iconName = iconName {
                savedWaypoints[index].iconName = iconName
            }
            savedWaypoints[index].lastUpdatedDate = Date()
            saveToStorage()
        }
    }
    
    func deleteWaypoint(at index: Int) {
        savedWaypoints.remove(at: index)
        saveToStorage()
    }
    
    func deleteWaypoint(id: UUID) {
        savedWaypoints.removeAll { $0.id == id }
        saveToStorage()
    }
    
    func fetchLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let name = placemark.locality ?? 
                          placemark.subLocality ?? 
                          placemark.thoroughfare ??
                          placemark.administrativeArea ?? 
                          "Unknown Location"
                completion(name)
            } else {
                completion("Unknown Location")
            }
        }
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(savedWaypoints) {
            UserDefaults.standard.set(encoded, forKey: "savedWaypoints")
        }
    }
    
    private func loadWaypoints() {
        if let data = UserDefaults.standard.data(forKey: "savedWaypoints"),
           let decoded = try? JSONDecoder().decode([Waypoint].self, from: data) {
            savedWaypoints = decoded
        }
    }
}