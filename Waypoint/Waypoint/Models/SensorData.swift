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

    var currentLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
    }
    
    var speedKmh: Double {
        calculatedSpeed * 3.6
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

    enum CodingKeys: String, CodingKey {
        case hasFix = "has_fix"
        case satellites
        case currentLat
        case currentLon
        case altitude
        case hdop
        case heading
    }
}