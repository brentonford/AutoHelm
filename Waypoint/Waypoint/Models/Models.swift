import Foundation
import CoreLocation
import SwiftUI

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
}

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

struct BleResponse: Codable, Equatable {
    let ack: String?
    let error: String?
}

enum ConnectionState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected"
}

enum JogDirection {
    case forward
    case back
    case left
    case right
}

class LocationWithSpeed {
    var coordinate: CLLocationCoordinate2D
    var speed: Double
    var timestamp: Date
    
    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastTimestamp: Date?
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        self.speed = 0
        self.timestamp = Date()
    }
    
    func updateLocation(_ newCoordinate: CLLocationCoordinate2D) {
        let now = Date()
        
        if let _ = lastCoordinate, let lastTime = lastTimestamp {
            let timeDiff = now.timeIntervalSince(lastTime)
            
            if timeDiff > 0 {
                let distance = coordinate.distance(to: newCoordinate)
                speed = distance / timeDiff
            }
        }
        
        lastCoordinate = coordinate
        lastTimestamp = timestamp
        coordinate = newCoordinate
        timestamp = now
    }
}

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