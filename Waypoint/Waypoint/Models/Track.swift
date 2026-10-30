import Foundation
import SwiftData
import CoreLocation

@Model
final class Track {
    var name: String
    var dateStarted: Date
    var dateEnded: Date?

    @Relationship(deleteRule: .cascade, inverse: \TrackPoint.track)
    var points: [TrackPoint]? = []

    init(name: String) {
        self.name = name
        self.dateStarted = Date()
    }

    var durationSeconds: TimeInterval {
        (dateEnded ?? Date()).timeIntervalSince(dateStarted)
    }

    /// Stored when the track is finalized in TrackRecorder.stopRecording().
    /// Zero for active (in-progress) tracks.
    var distanceMetres: Double = 0

    var totalDistanceMetres: Double {
        if dateEnded != nil && distanceMetres > 0 {
            return distanceMetres  // pre-computed at finalization, avoids O(n) sort on every render
        }
        // Active track or pre-migration track: compute live
        guard (points?.count ?? 0) > 1 else { return 0 }
        let sorted = (points ?? []).sorted { $0.timestamp < $1.timestamp }
        var dist = 0.0
        for i in 1..<sorted.count {
            dist += sorted[i - 1].coordinate.distance(to: sorted[i].coordinate)
        }
        return dist
    }
}

@Model
final class TrackPoint {
    var latitude: Double
    var longitude: Double
    var speedKmh: Double
    var timestamp: Date

    // Optional back-reference mirrors CloudKit/cascade requirements on Waypoint.
    var track: Track?

    init(latitude: Double, longitude: Double, speedKmh: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.timestamp = Date()
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
