import Foundation
import CoreLocation

// MARK: - Waypoint

struct Waypoint: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String
    var dateCreated: Date
    var dateModified: Date
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, name: String = "", dateCreated: Date = Date(), dateModified: Date = Date()) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
    
    mutating func updateName(_ newName: String) {
        name = newName
        dateModified = Date()
    }
    
    func toGpsString() -> String {
        return String(format: "$GPS,%.6f,%.6f,0*", coordinate.latitude, coordinate.longitude)
    }
}

// MARK: - Device Status

struct DeviceStatus: Codable {
    let hasFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let hdop: Double
    let heading: Double
    let distance: Double
    let bearing: Double
    let relative: Double?
    let targetLat: Double?
    let targetLon: Double?
    let hasTarget: Bool?
    
    var currentLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
    }
    
    var targetLocation: CLLocationCoordinate2D? {
        guard let lat = targetLat, let lon = targetLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var isNavigationReady: Bool {
        hasFix && satellites >= 4 && hdop < 5.0
    }
    
    enum CodingKeys: String, CodingKey {
        case hasFix = "has_fix"
        case satellites
        case currentLat
        case currentLon
        case altitude
        case hdop
        case heading
        case distance
        case bearing
        case relative
        case targetLat
        case targetLon
        case hasTarget
    }
}

// MARK: - BLE Response

struct BleResponse: Codable, Equatable {
    let ack: String?
    let error: String?
}

// MARK: - Connection State

enum ConnectionState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected"
}

// MARK: - CLLocationCoordinate2D Codable

extension CLLocationCoordinate2D: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}