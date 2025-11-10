import Foundation
import CoreLocation

struct Waypoint: Identifiable, Codable {
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
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
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
    let heading: Double
    let distance: Double
    let bearing: Double
}