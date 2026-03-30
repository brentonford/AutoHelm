import Foundation
import CoreLocation

struct SensorData: Codable, Equatable {
    let hasFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let hdop: Double
    let heading: Double
    var calculatedSpeed: Double = 0

    // SpotLock telemetry (device-side algorithm, present when sl_active = true)
    var slActive:   Bool?
    var slLat:      Double?
    var slLon:      Double?
    var slDist:     Double?
    var slBearing:  Double?
    var slSpeed:    Int?
    var slRotation: Double?
    var slTangled:  Bool?
    var slThrust:   Bool?

    var currentLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
    }

    var speedKmh: Double { calculatedSpeed * 3.6 }

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

    // Convenience accessors with safe defaults
    var isSpotLockActive:     Bool   { slActive ?? false }
    var spotLockLocation: CLLocationCoordinate2D? {
        guard isSpotLockActive, let lat = slLat, let lon = slLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    var spotLockDistance:     Double { slDist     ?? 0 }
    var spotLockBearing:      Double { slBearing  ?? 0 }
    var spotLockSpeed:        Int    { slSpeed    ?? 0 }
    var spotLockRotation:     Double { slRotation ?? 0 }
    var spotLockTangled:      Bool   { slTangled  ?? false }
    var spotLockThrust:       Bool   { slThrust   ?? false }

    enum CodingKeys: String, CodingKey {
        case hasFix      = "has_fix"
        case satellites
        case currentLat
        case currentLon
        case altitude
        case hdop
        case heading
        case slActive    = "sl_active"
        case slLat       = "sl_lat"
        case slLon       = "sl_lon"
        case slDist      = "sl_dist"
        case slBearing   = "sl_bearing"
        case slSpeed     = "sl_speed"
        case slRotation  = "sl_rotation"
        case slTangled   = "sl_tangled"
        case slThrust    = "sl_thrust"
    }
}