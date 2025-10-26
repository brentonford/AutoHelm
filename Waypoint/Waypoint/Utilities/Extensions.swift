import SwiftUI
import CoreLocation
import MapKit

// MARK: - Array Extensions
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - CLLocationCoordinate2D Extensions
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
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

// MARK: - ArduinoNavigationStatus Extensions
extension ArduinoNavigationStatus {
    var statusColor: Color {
        if hasGpsFix {
            return .green
        }
        return .red
    }
    
    var navigationStatusText: String {
        if hasReachedDestination ?? false {
            return "Destination Reached"
        } else if isNavigating ?? false {
            return "Navigating"
        } else if navigationActive {
            return "Ready"
        }
        return "Standby"
    }
    
    var navigationStatusColor: Color {
        if hasReachedDestination ?? false {
            return .green
        } else if isNavigating ?? false {
            return .blue
        } else if navigationActive {
            return .orange
        }
        return .gray
    }
}

// MARK: - Date Extensions
extension Date {
    var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}