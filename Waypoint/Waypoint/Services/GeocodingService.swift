import Foundation
import CoreLocation

/// Reverse-geocodes coordinates to human-readable place names.
/// Prioritises: inland water > area of interest > sub-locality > locality.
/// Results are cached by rounded coordinate (~111 m grid) to avoid repeat API calls.
@MainActor
final class GeocodingService {
    static let shared = GeocodingService()

    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    private init() {}

    func locationName(for coordinate: CLLocationCoordinate2D) async -> String {
        let key = cacheKey(for: coordinate)
        if let cached = cache[key] { return cached }

        // CLGeocoder supports only one request at a time and enforces ~1 req/sec.
        // Cancel any in-flight request before starting a new one so rapid pin drops
        // don't queue up and get rate-limited.
        geocoder.cancelGeocode()

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let name = bestName(from: placemarks.first) ?? fallback(coordinate)
            cache[key] = name
            return name
        } catch {
            return fallback(coordinate)
        }
    }

    private func bestName(from placemark: CLPlacemark?) -> String? {
        guard let p = placemark else { return nil }
        if let body = p.inlandWater              { return body }
        if let poi  = p.areasOfInterest?.first   { return poi }
        if let sub  = p.subLocality              { return sub }
        if let loc  = p.locality                 { return loc }
        return nil
    }

    private func cacheKey(for c: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }

    private func fallback(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }
}
