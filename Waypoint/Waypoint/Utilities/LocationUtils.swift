import CoreLocation
import MapKit

class LocationUtils {
    static func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    static func formatDistance(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    static func formatCoordinate(_ coordinate: CLLocationCoordinate2D, style: CoordinateDisplayStyle = .decimal) -> String {
        switch style {
        case .decimal:
            return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        case .degreeMinuteSecond:
            return formatDMS(coordinate)
        }
    }
    
    private static func formatDMS(_ coordinate: CLLocationCoordinate2D) -> String {
        let latDMS = convertToDMS(coordinate.latitude, isLatitude: true)
        let lonDMS = convertToDMS(coordinate.longitude, isLatitude: false)
        return "\(latDMS), \(lonDMS)"
    }
    
    private static func convertToDMS(_ coordinate: Double, isLatitude: Bool) -> String {
        let absoluteCoordinate = abs(coordinate)
        let degrees = Int(absoluteCoordinate)
        let minutes = Int((absoluteCoordinate - Double(degrees)) * 60)
        let seconds = ((absoluteCoordinate - Double(degrees)) * 60 - Double(minutes)) * 60
        
        let direction = isLatitude ? 
            (coordinate >= 0 ? "N" : "S") : 
            (coordinate >= 0 ? "E" : "W")
        
        return String(format: "%d°%d'%.2f\"%@", degrees, minutes, seconds, direction)
    }
}

enum CoordinateDisplayStyle {
    case decimal
    case degreeMinuteSecond
}