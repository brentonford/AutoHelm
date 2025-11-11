import Foundation
import CoreLocation

struct Waypoint: Identifiable, Codable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    var name: String
    var comments: String
    var photoData: Data?
    var iconName: String
    let createdDate: Date
    var lastUpdatedDate: Date
    
    init(coordinate: CLLocationCoordinate2D, name: String = "Waypoint", comments: String = "", iconName: String = "mappin.circle.fill") {
        self.id = UUID()
        self.coordinate = coordinate
        self.name = name
        self.comments = comments
        self.photoData = nil
        self.iconName = iconName
        self.createdDate = Date()
        self.lastUpdatedDate = Date()
    }
    
    mutating func updateLastModified() {
        self.lastUpdatedDate = Date()
    }
    
    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        return lhs.id == rhs.id
    }
}

extension CLLocationCoordinate2D: Codable, @retroactive Equatable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return abs(lhs.latitude - rhs.latitude) < 0.000001 && 
               abs(lhs.longitude - rhs.longitude) < 0.000001
    }
    
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

struct DeviceStatus: Codable {
    let hasGpsFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let speedKnots: Double?
    let time: String?
    let date: String?
    let hdop: Double?
    let vdop: Double?
    let pdop: Double?
    let heading: Double
    let distance: Double
    let bearing: Double
    let targetLat: Double?
    let targetLon: Double?
    
    var currentCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
    }
    
    var targetCoordinate: CLLocationCoordinate2D? {
        guard let lat = targetLat, let lon = targetLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var gpsAccuracyDescription: String {
        guard let hdop = hdop else { return "Unknown" }
        
        switch hdop {
        case 0..<1:
            return "Excellent"
        case 1..<2:
            return "Good"
        case 2..<5:
            return "Moderate"
        case 5..<10:
            return "Fair"
        case 10..<20:
            return "Poor"
        default:
            return "Very Poor"
        }
    }
}

enum NavigationState: Equatable {
    case idle
    case navigating
    case arrived
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .navigating:
            return "Navigating"
        case .arrived:
            return "Arrived"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.navigating, .navigating), (.arrived, .arrived):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

struct SystemConfig {
    static let maxWaypoints: Int = 50
    static let waypointArrivalDistance: Double = 5.0 // meters
    static let coordinatePrecision: Int = 6
    static let autoSaveInterval: TimeInterval = 30.0 // seconds
    
    static func formatCoordinate(_ value: Double) -> String {
        return String(format: "%.\(coordinatePrecision)f", value)
    }
}