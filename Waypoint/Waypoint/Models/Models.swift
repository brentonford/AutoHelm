import Foundation
import CoreLocation
import SwiftUI

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

    var gpsQuality: GPSQuality {
        if !hasFix { return .noFix }
        if satellites < 4 { return .poor }
        if hdop >= 5.0 { return .poor }
        if hdop >= 2.0 { return .fair }
        if hdop >= 1.0 { return .good }
        return .excellent
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
    
    var isActiveNavigation: Bool {
        hasTarget == true && (navState == "navigating" || navState == "path" || navState == "spotlock")
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

// MARK: - GPS Quality

enum GPSQuality {
    case noFix
    case poor
    case fair
    case good
    case excellent
    
    var color: Color {
        switch self {
        case .noFix: return .red
        case .poor: return .orange
        case .fair: return .yellow
        case .good, .excellent: return .green
        }
    }
    
    var icon: String {
        switch self {
        case .noFix:
            return "antenna.radiowaves.left.and.right.slash"
        case .poor, .fair, .good, .excellent:
            return "antenna.radiowaves.left.and.right"
        }
    }
    
    var label: String {
        switch self {
        case .noFix: return "No Fix"
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}

// MARK: - BLE Signal Strength

enum BLESignalStrength {
    case disconnected
    case weak
    case fair
    case good
    case excellent
    
    static func from(rssi: Int) -> BLESignalStrength {
        if rssi >= -50 { return .excellent }
        if rssi >= -60 { return .good }
        if rssi >= -70 { return .fair }
        if rssi >= -80 { return .weak }
        return .disconnected
    }
    
    var color: Color {
        switch self {
        case .disconnected: return .red
        case .weak: return .orange
        case .fair: return .yellow
        case .good, .excellent: return .green
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .weak, .fair, .good, .excellent:
            return "wifi"
        }
    }
    
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
    
    var bars: Int {
        switch self {
        case .disconnected: return 0
        case .weak: return 1
        case .fair: return 2
        case .good: return 3
        case .excellent: return 4
        }
    }
}

// MARK: - Waypoint Preview

struct WaypointPreview {
    let waypoint: Waypoint
    let distance: Double
    let bearing: Double
    let estimatedTime: TimeInterval
    
    var distanceString: String {
        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }
    
    var bearingString: String {
        String(format: "%.0f deg", bearing)
    }
    
    var estimatedTimeString: String {
        let minutes = Int(estimatedTime / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    var cardinalDirection: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5) / 45.0) % 8
        return directions[index]
    }
}

// MARK: - Track Point

struct TrackPoint: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    
    init(coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.id = UUID()
        self.coordinate = coordinate
        self.timestamp = timestamp
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

// MARK: - Navigation Helpers

extension CLLocationCoordinate2D {
    
    private static let earthRadiusMeters: Double = 6371000.0
    
    func distance(to destination: CLLocationCoordinate2D) -> Double {
        let lat1Rad = latitude * .pi / 180
        let lat2Rad = destination.latitude * .pi / 180
        let deltaLat = (destination.latitude - latitude) * .pi / 180
        let deltaLon = (destination.longitude - longitude) * .pi / 180
        
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return Self.earthRadiusMeters * c
    }
    
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1Rad = latitude * .pi / 180
        let lat2Rad = destination.latitude * .pi / 180
        let deltaLon = (destination.longitude - longitude) * .pi / 180
        
        let x = sin(deltaLon) * cos(lat2Rad)
        let y = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLon)
        
        var bearing = atan2(x, y) * 180 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
        
        return bearing
    }
}