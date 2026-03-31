import UIKit

/// Manages full-resolution waypoint photos on disk.
/// Only thumbnails are stored inline in the SwiftData model; full images live in Documents/WaypointPhotos/.
final class WaypointPhotoStore {
    static let shared = WaypointPhotoStore()

    private let folder: URL
    private let thumbnailMaxDimension: CGFloat = 120

    private init() {
        folder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WaypointPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Saves a full-resolution image to the local disk cache.
    /// Returns (filename, thumbnailData, imageData) or nil on failure.
    /// The caller stores imageData in the WaypointPhoto model so it syncs as a CloudKit Asset.
    func save(_ image: UIImage) -> (filename: String, thumbnail: Data, imageData: Data)? {
        let filename = "\(UUID().uuidString).jpg"
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try jpeg.write(to: folder.appendingPathComponent(filename))
        } catch {
            print("[PhotoStore] write failed: \(error)")
            return nil
        }
        guard let thumbData = makeThumbnail(image).jpegData(compressionQuality: 0.7) else { return nil }
        return (filename, thumbData, jpeg)
    }

    /// Loads a full-resolution image. Checks the local disk cache first; if missing,
    /// uses `fallback` data from the model (CloudKit Asset) and repopulates the cache.
    func load(filename: String, fallback: Data? = nil) -> UIImage? {
        let url = folder.appendingPathComponent(filename)
        if let cached = UIImage(contentsOfFile: url.path) {
            return cached
        }
        // Local file missing — photo was synced from CloudKit on another device.
        // Materialise from model data and restore the disk cache.
        if let data = fallback, let image = UIImage(data: data) {
            try? data.write(to: url)
            return image
        }
        return nil
    }

    func delete(filename: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(filename))
    }

    /// Removes any photo files on disk that are not referenced by a known WaypointPhoto model.
    /// Call this on app foreground or when the waypoint list appears to recover orphaned disk space.
    func cleanupOrphans(keeping knownFilenames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in contents where !knownFilenames.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private func makeThumbnail(_ image: UIImage) -> UIImage {
        let scale = min(thumbnailMaxDimension / image.size.width,
                        thumbnailMaxDimension / image.size.height)
        let size = CGSize(width:  image.size.width  * scale,
                          height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
