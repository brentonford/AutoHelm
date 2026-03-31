import Foundation
import SwiftData
import CoreLocation

@Model
final class Waypoint {
    var name: String
    var notes: String
    var latitude: Double
    var longitude: Double
    var dateCreated: Date

    // Optional array + explicit inverse are both required by CloudKit.
    // Non-optional arrays and missing inverses crash ModelContainer creation
    // on iOS 17.4+ and cause silent sync failures on iOS 18.
    @Relationship(deleteRule: .cascade, inverse: \WaypointPhoto.waypoint)
    var photos: [WaypointPhoto]? = []

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.notes = ""
        self.latitude = latitude
        self.longitude = longitude
        self.dateCreated = Date()
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceMetres(from other: CLLocationCoordinate2D) -> Double {
        coordinate.distance(to: other)
    }
}

@Model
final class WaypointPhoto {
    var filename: String
    var thumbnailData: Data
    var dateAdded: Date

    // Optional back-reference required by CloudKit (non-optional inverses break cascade delete).
    var waypoint: Waypoint?

    init(filename: String, thumbnailData: Data) {
        self.filename = filename
        self.thumbnailData = thumbnailData
        self.dateAdded = Date()
    }
}
