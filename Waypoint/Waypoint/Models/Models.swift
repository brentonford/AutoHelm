import Foundation
import CoreLocation

// MARK: - Waypoint

struct Waypoint: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String
    var dateCreated: Date
    var dateModified: Date
    var spotLockEnabled: Bool
    var approachSpeed: Double
    var arrivalRadius: Double

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        name: String = "",
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        spotLockEnabled: Bool = false,
        approachSpeed: Double = 0,
        arrivalRadius: Double = 5.0
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.spotLockEnabled = spotLockEnabled
        self.approachSpeed = approachSpeed
        self.arrivalRadius = arrivalRadius
    }

    mutating func updateName(_ newName: String) {
        name = newName
        dateModified = Date()
    }

    func toGpsString() -> String {
        let safeName = name.replacingOccurrences(of: ",", with: " ")
        return String(
            format: "$GPS,%.6f,%.6f,0,%@,%d,%.1f*",
            coordinate.latitude,
            coordinate.longitude,
            safeName,
            spotLockEnabled ? 1 : 0,
            approachSpeed
        )
    }
}

// MARK: - Path

struct Path: Identifiable, Codable {
    let id: UUID
    var name: String
    var waypoints: [Waypoint]
    var defaultSpeed: Double
    var loop: Bool
    var dateCreated: Date
    var dateModified: Date

    init(name: String = "New Path") {
        self.id = UUID()
        self.name = name
        self.waypoints = []
        self.defaultSpeed = 3.6
        self.loop = false
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    mutating func addWaypoint(_ waypoint: Waypoint) {
        waypoints.append(waypoint)
        dateModified = Date()
    }

    mutating func removeWaypoint(at index: Int) {
        guard index >= 0 && index < waypoints.count else { return }
        waypoints.remove(at: index)
        dateModified = Date()
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
    let navState: String?
    let speedLevel: Int?
    let targetSpeed: Int?
    let speedKmh: Double?

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

    var isSpotLockActive: Bool {
        navState == "spotlock"
    }

    var isPathFollowing: Bool {
        navState == "path"
    }

    var isNavigating: Bool {
        navState == "navigating" || navState == "path"
    }

    var isManualMode: Bool {
        navState == "manual"
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
        case navState
        case speedLevel
        case targetSpeed
        case speedKmh
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

// MARK: - Jog Direction

enum JogDirection {
    case forward
    case back
    case left
    case right
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