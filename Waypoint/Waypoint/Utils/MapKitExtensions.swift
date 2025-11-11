import MapKit
import SwiftUI
import Combine
import Foundation

// MARK: - Custom Annotation Types
enum WaypointAnnotationType {
    case standard
    case favorite
    case recent
    case destination
    
    var imageName: String {
        switch self {
        case .standard: return "mappin.circle.fill"
        case .favorite: return "star.circle.fill"
        case .recent: return "clock.circle.fill" 
        case .destination: return "flag.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .standard: return .red
        case .favorite: return .yellow
        case .recent: return .blue
        case .destination: return .green
        }
    }
}

// MARK: - Enhanced Waypoint Annotation
class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: Waypoint
    let annotationType: WaypointAnnotationType
    
    var coordinate: CLLocationCoordinate2D {
        waypoint.coordinate
    }
    
    var title: String? {
        waypoint.name
    }
    
    var subtitle: String? {
        waypoint.comments.isEmpty ? nil : waypoint.comments
    }
    
    init(waypoint: Waypoint, type: WaypointAnnotationType = .standard) {
        self.waypoint = waypoint
        self.annotationType = type
        super.init()
    }
}

// MARK: - Annotation Clustering Manager
@MainActor
class AnnotationClusteringManager: ObservableObject {
    @Published var clusteredAnnotations: [MKAnnotation] = []
    @Published var clusteringEnabled: Bool = true
    @Published var clusterRadius: Double = 100.0 // meters
    
    private let logger = AppLogger.shared
    
    func clusterAnnotations(_ annotations: [WaypointAnnotation], in region: MKCoordinateRegion) -> [MKAnnotation] {
        logger.startPerformanceMeasurement("annotation_clustering", category: .mapkit)
        defer { logger.endPerformanceMeasurement("annotation_clustering", category: .mapkit) }
        
        guard clusteringEnabled && annotations.count > 1 else {
            return annotations
        }
        
        var clusters: [AnnotationCluster] = []
        var processed: Set<WaypointAnnotation> = []
        
        for annotation in annotations {
            guard !processed.contains(annotation) else { continue }
            
            let nearbyAnnotations = findNearbyAnnotations(
                to: annotation,
                in: annotations,
                radius: clusterRadius
            ).filter { !processed.contains($0) }
            
            if nearbyAnnotations.count > 1 {
                let cluster = AnnotationCluster(annotations: nearbyAnnotations)
                clusters.append(cluster)
                nearbyAnnotations.forEach { processed.insert($0) }
            } else {
                processed.insert(annotation)
            }
        }
        
        let unclustered = annotations.filter { !processed.contains($0) }
        let result = clusters + unclustered
        
        logger.debug("Clustered \(annotations.count) annotations into \(result.count) items", category: .mapkit)
        
        return result.compactMap { $0 as? MKAnnotation }
    }
    
    private func findNearbyAnnotations(to target: WaypointAnnotation, in annotations: [WaypointAnnotation], radius: Double) -> [WaypointAnnotation] {
        let targetLocation = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        
        return annotations.filter { annotation in
            let annotationLocation = CLLocation(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude)
            return targetLocation.distance(from: annotationLocation) <= radius
        }
    }
    
    func updateClusterRadius(_ radius: Double) {
        clusterRadius = radius
        logger.debug("Cluster radius updated to \(radius)m", category: .mapkit)
    }
    
    func toggleClustering() {
        clusteringEnabled.toggle()
        logger.info("Annotation clustering \(clusteringEnabled ? "enabled" : "disabled")", category: .mapkit)
    }
}

// MARK: - Annotation Cluster
class AnnotationCluster: NSObject, MKAnnotation {
    let annotations: [WaypointAnnotation]
    
    var coordinate: CLLocationCoordinate2D {
        let totalLat = annotations.reduce(0) { $0 + $1.coordinate.latitude }
        let totalLon = annotations.reduce(0) { $0 + $1.coordinate.longitude }
        let count = Double(annotations.count)
        
        return CLLocationCoordinate2D(
            latitude: totalLat / count,
            longitude: totalLon / count
        )
    }
    
    var title: String? {
        return "\(annotations.count) Waypoints"
    }
    
    var subtitle: String? {
        let types = Set(annotations.map { $0.annotationType })
        return "Types: \(types.count)"
    }
    
    init(annotations: [WaypointAnnotation]) {
        self.annotations = annotations
        super.init()
    }
}

// MARK: - Offline Tile Manager
@MainActor
class OfflineTileManager: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadedRegions: [OfflineMapRegion] = []
    @Published var totalCacheSize: Int64 = 0
    
    private let logger = AppLogger.shared
    private let cacheDirectory: URL
    private var currentDownloadTask: URLSessionDownloadTask?
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("OfflineMapTiles")
        
        createCacheDirectoryIfNeeded()
        loadDownloadedRegions()
        calculateCacheSize()
    }
    
    // MARK: - Cache Management
    private func createCacheDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func loadDownloadedRegions() {
        let regionsFile = cacheDirectory.appendingPathComponent("regions.json")
        
        guard let data = try? Data(contentsOf: regionsFile),
              let regions = try? JSONDecoder().decode([OfflineMapRegion].self, from: data) else {
            logger.debug("No existing offline regions found", category: .mapkit)
            return
        }
        
        downloadedRegions = regions
        logger.info("Loaded \(regions.count) offline map regions", category: .mapkit)
    }
    
    private func saveDownloadedRegions() {
        let regionsFile = cacheDirectory.appendingPathComponent("regions.json")
        
        do {
            let data = try JSONEncoder().encode(downloadedRegions)
            try data.write(to: regionsFile)
            logger.debug("Saved offline regions to disk", category: .mapkit)
        } catch {
            logger.error("Failed to save offline regions", error: error, category: .mapkit)
        }
    }
    
    func calculateCacheSize() {
        Task {
            do {
                let resourceKeys: [URLResourceKey] = [.fileSizeKey]
                let enumerator = FileManager.default.enumerator(
                    at: cacheDirectory,
                    includingPropertiesForKeys: resourceKeys
                )
                
                var totalSize: Int64 = 0
                
                while let fileURL = enumerator?.nextObject() as? URL {
                    let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
                
                await MainActor.run {
                    self.totalCacheSize = totalSize
                    logger.debug("Cache size calculated: \(self.formatFileSize(totalSize))", category: .mapkit)
                }
            } catch {
                logger.error("Failed to calculate cache size", error: error, category: .mapkit)
            }
        }
    }
    
    // MARK: - Tile Downloads
    func downloadTiles(for region: MKCoordinateRegion, minZoom: Int = 10, maxZoom: Int = 16, name: String) async throws {
        logger.startPerformanceMeasurement("tile_download", category: .mapkit)
        logger.info("Starting tile download for region: \(name)", category: .mapkit)
        
        isDownloading = true
        downloadProgress = 0.0
        
        defer {
            isDownloading = false
            logger.endPerformanceMeasurement("tile_download", category: .mapkit)
        }
        
        let tileUrls = generateTileUrls(for: region, minZoom: minZoom, maxZoom: maxZoom)
        let totalTiles = tileUrls.count
        
        logger.info("Generated \(totalTiles) tile URLs for download", category: .mapkit)
        
        var downloadedCount = 0
        
        for (_, tileUrl) in tileUrls.enumerated() {
            do {
                try await downloadSingleTile(tileUrl)
                downloadedCount += 1
                
                await MainActor.run {
                    self.downloadProgress = Double(downloadedCount) / Double(totalTiles)
                }
            } catch {
                logger.warning("Failed to download tile: \(tileUrl)", category: .mapkit)
            }
        }
        
        let offlineRegion = OfflineMapRegion(
            id: UUID(),
            name: name,
            region: region,
            minZoom: minZoom,
            maxZoom: maxZoom,
            downloadDate: Date(),
            tileCount: downloadedCount
        )
        
        downloadedRegions.append(offlineRegion)
        saveDownloadedRegions()
        calculateCacheSize()
        
        logger.info("Completed tile download: \(downloadedCount)/\(totalTiles) tiles for \(name)", category: .mapkit)
    }
    
    private func downloadSingleTile(_ tileUrl: TileURL) async throws {
        let url = buildOpenStreetMapURL(for: tileUrl)
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let localPath = cacheDirectory
            .appendingPathComponent("\(tileUrl.z)")
            .appendingPathComponent("\(tileUrl.x)")
        
        try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)
        
        let filePath = localPath.appendingPathComponent("\(tileUrl.y).png")
        try data.write(to: filePath)
    }
    
    private func buildOpenStreetMapURL(for tileUrl: TileURL) -> URL {
        // Using OpenStreetMap tile server
        let urlString = "https://tile.openstreetmap.org/\(tileUrl.z)/\(tileUrl.x)/\(tileUrl.y).png"
        return URL(string: urlString)!
    }
    
    private func generateTileUrls(for region: MKCoordinateRegion, minZoom: Int, maxZoom: Int) -> [TileURL] {
        var urls: [TileURL] = []
        
        for zoom in minZoom...maxZoom {
            let tiles = tilesForRegion(region, zoom: zoom)
            urls.append(contentsOf: tiles)
        }
        
        return urls
    }
    
    private func tilesForRegion(_ region: MKCoordinateRegion, zoom: Int) -> [TileURL] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        
        let minTileX = Int(floor((minLon + 180.0) / 360.0 * Double(1 << zoom)))
        let maxTileX = Int(floor((maxLon + 180.0) / 360.0 * Double(1 << zoom)))
        
        let minTileY = Int(floor((1.0 - asinh(tan(minLat * .pi / 180.0)) / .pi) / 2.0 * Double(1 << zoom)))
        let maxTileY = Int(floor((1.0 - asinh(tan(maxLat * .pi / 180.0)) / .pi) / 2.0 * Double(1 << zoom)))
        
        var tiles: [TileURL] = []
        
        for x in minTileX...maxTileX {
            for y in min(minTileY, maxTileY)...max(minTileY, maxTileY) {
                tiles.append(TileURL(x: x, y: y, z: zoom))
            }
        }
        
        return tiles
    }
    
    // MARK: - Cache Operations
    func clearCache() async {
        logger.info("Clearing offline map cache", category: .mapkit)
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            
            for item in contents {
                try FileManager.default.removeItem(at: item)
            }
            
            await MainActor.run {
                self.downloadedRegions.removeAll()
                self.totalCacheSize = 0
                self.saveDownloadedRegions()
            }
            
            logger.info("Offline map cache cleared successfully", category: .mapkit)
        } catch {
            logger.error("Failed to clear cache", error: error, category: .mapkit)
        }
    }
    
    func deleteRegion(_ region: OfflineMapRegion) {
        guard let index = downloadedRegions.firstIndex(where: { $0.id == region.id }) else { return }
        
        downloadedRegions.remove(at: index)
        saveDownloadedRegions()
        calculateCacheSize()
        
        logger.info("Deleted offline region: \(region.name)", category: .mapkit)
    }
    
    func getCachedTile(x: Int, y: Int, z: Int) -> UIImage? {
        let tilePath = cacheDirectory
            .appendingPathComponent("\(z)")
            .appendingPathComponent("\(x)")
            .appendingPathComponent("\(y).png")
        
        guard FileManager.default.fileExists(atPath: tilePath.path) else { return nil }
        return UIImage(contentsOfFile: tilePath.path)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func getFormattedCacheSize() -> String {
        formatFileSize(totalCacheSize)
    }
}

// MARK: - Supporting Data Models
struct TileURL: Hashable {
    let x: Int
    let y: Int
    let z: Int
}

struct OfflineMapRegion: Identifiable, Codable {
    let id: UUID
    let name: String
    let region: MKCoordinateRegion
    let minZoom: Int
    let maxZoom: Int
    let downloadDate: Date
    let tileCount: Int
    
    var formattedSize: String {
        let estimatedSize = Int64(tileCount * 20000) // Rough estimate
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: estimatedSize)
    }
}

extension MKCoordinateRegion: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(center.latitude, forKey: .centerLatitude)
        try container.encode(center.longitude, forKey: .centerLongitude)
        try container.encode(span.latitudeDelta, forKey: .spanLatitudeDelta)
        try container.encode(span.longitudeDelta, forKey: .spanLongitudeDelta)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let centerLat = try container.decode(CLLocationDegrees.self, forKey: .centerLatitude)
        let centerLon = try container.decode(CLLocationDegrees.self, forKey: .centerLongitude)
        let spanLat = try container.decode(CLLocationDegrees.self, forKey: .spanLatitudeDelta)
        let spanLon = try container.decode(CLLocationDegrees.self, forKey: .spanLongitudeDelta)
        
        self.init(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }
    
    private enum CodingKeys: String, CodingKey {
        case centerLatitude, centerLongitude, spanLatitudeDelta, spanLongitudeDelta
    }
}

// MARK: - Advanced Waypoint Visualization
struct WaypointClusterView: View {
    let cluster: AnnotationCluster
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 40, height: 40)
            
            Circle()
                .fill(Color.blue)
                .frame(width: 30, height: 30)
            
            Text("\(cluster.annotations.count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

struct EnhancedWaypointAnnotationView: View {
    let annotation: WaypointAnnotation
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(annotation.annotationType.color.opacity(0.3))
                    .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
                
                Circle()
                    .fill(annotation.annotationType.color)
                    .frame(width: isSelected ? 40 : 30, height: isSelected ? 40 : 30)
                
                Image(systemName: annotation.annotationType.imageName)
                    .foregroundColor(.white)
                    .font(.system(size: isSelected ? 16 : 12, weight: .bold))
            }
            
            if isSelected {
                Text(annotation.waypoint.name)
                    .font(.caption)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - MapKit Utilities
extension MapKitExtensions {
    static func calculateOptimalRegion(for waypoints: [Waypoint], padding: Double = 1.5) -> MKCoordinateRegion? {
        guard !waypoints.isEmpty else { return nil }
        
        if waypoints.count == 1 {
            return MKCoordinateRegion(
                center: waypoints.first!.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        let coordinates = waypoints.map { $0.coordinate }
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * padding,
            longitudeDelta: (maxLon - minLon) * padding
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct MapKitExtensions {
    // Utility struct to hold static methods
}