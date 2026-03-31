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

    /// Saves a full-resolution image. Returns (filename, thumbnailData) or nil on failure.
    func save(_ image: UIImage) -> (filename: String, thumbnail: Data)? {
        let filename = "\(UUID().uuidString).jpg"
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try jpeg.write(to: folder.appendingPathComponent(filename))
        } catch {
            print("[PhotoStore] write failed: \(error)")
            return nil
        }
        guard let thumbData = makeThumbnail(image).jpegData(compressionQuality: 0.7) else { return nil }
        return (filename, thumbData)
    }

    func load(filename: String) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(filename).path)
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
