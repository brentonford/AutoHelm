import Foundation
import SwiftData
import CoreLocation

@Model
final class Waypoint {
    // Default values are required by CloudKit — all non-optional attributes must have
    // a default so CloudKit can deserialise records that are missing fields.
    var name: String = ""
    var notes: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var dateCreated: Date = Date()

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
    var filename: String = ""
    var thumbnailData: Data = Data()
    var dateAdded: Date = Date()

    // Optional back-reference required by CloudKit (non-optional inverses break cascade delete).
    var waypoint: Waypoint?

    // Full-resolution JPEG stored externally by SwiftData and synced as a CKAsset by CloudKit.
    // Nil for photos added before this version — those fall back to the local disk cache.
    @Attribute(.externalStorage) var imageData: Data?

    init(filename: String, thumbnailData: Data, imageData: Data? = nil) {
        self.filename = filename
        self.thumbnailData = thumbnailData
        self.imageData = imageData
        self.dateAdded = Date()
    }
}
