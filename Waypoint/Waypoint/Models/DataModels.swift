import SwiftUI
import CoreLocation
import MapKit

// MARK: - Magnetometer Calibration Model
struct MagnetometerData: Codable {
    let x: Float
    let y: Float
    let z: Float
    let minX: Float
    let minY: Float
    let minZ: Float
    let maxX: Float
    let maxY: Float
    let maxZ: Float
}

// MARK: - Arduino Navigation Status Model
struct ArduinoNavigationStatus: Equatable, Decodable {
    let navigationActive: Bool
    let hasGpsFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let heading: Float
    let bearing: Float
    let distance: Float
    let targetLat: Double
    let targetLon: Double
    let isNavigating: Bool?
    let hasReachedDestination: Bool?
    
    var distanceText: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    var destinationReached: Bool {
        return hasReachedDestination ?? false
    }
}

// MARK: - Waypoint Model
struct Waypoint: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let createdDate: Date
    var lastUpdatedDate: Date
    var name: String
    var isSaved: Bool
    var comments: String
    var photoData: Data?
    var iconName: String
    
    init(coordinate: CLLocationCoordinate2D, name: String = "New Waypoint", isSaved: Bool = false) {
        self.id = UUID()
        self.coordinate = coordinate
        self.createdDate = Date()
        self.lastUpdatedDate = Date()
        self.name = name
        self.isSaved = isSaved
        self.comments = ""
        self.photoData = nil
        self.iconName = "mappin.circle.fill"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, createdDate, lastUpdatedDate, name, isSaved, comments, photoData, iconName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
        lastUpdatedDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedDate) ?? Date()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Waypoint"
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        comments = try container.decodeIfPresent(String.self, forKey: .comments) ?? ""
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "mappin.circle.fill"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastUpdatedDate, forKey: .lastUpdatedDate)
        try container.encode(name, forKey: .name)
        try container.encode(isSaved, forKey: .isSaved)
        try container.encode(comments, forKey: .comments)
        try container.encode(photoData, forKey: .photoData)
        try container.encode(iconName, forKey: .iconName)
    }
}

// MARK: - Downloaded Region Model
struct DownloadedRegion: Identifiable, Codable {
    let id: UUID
    let center: CLLocationCoordinate2D
    let radiusKm: Double
    let downloadDate: Date
    var lastUpdated: Date
    var name: String
    
    init(center: CLLocationCoordinate2D, radiusKm: Double, name: String = "Unnamed Region") {
        self.id = UUID()
        self.center = center
        self.radiusKm = radiusKm
        self.downloadDate = Date()
        self.lastUpdated = Date()
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case id, centerLat, centerLon, radiusKm, downloadDate, lastUpdated, name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .centerLat)
        let lon = try container.decode(Double.self, forKey: .centerLon)
        center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        radiusKm = try container.decode(Double.self, forKey: .radiusKm)
        downloadDate = try container.decode(Date.self, forKey: .downloadDate)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? downloadDate
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Region"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center.latitude, forKey: .centerLat)
        try container.encode(center.longitude, forKey: .centerLon)
        try container.encode(radiusKm, forKey: .radiusKm)
        try container.encode(downloadDate, forKey: .downloadDate)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(name, forKey: .name)
    }
}

// MARK: - Helper Extensions
// Array safe subscript extension is implemented in Extensions.swift to avoid duplication