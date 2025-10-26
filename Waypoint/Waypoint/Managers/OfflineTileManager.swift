import SwiftUI
import MapKit
import CoreLocation

class OfflineTileManager: ObservableObject {
    @Published var downloadedRegions: [DownloadedRegion] = []
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadedTilesCount: Int = 0
    @Published var totalTilesCount: Int = 0
    @Published var cacheSize: Int64 = 0
    
    private var downloadTask: URLSessionDataTask?
    private let session = URLSession.shared
    private let fileManager = FileManager.default
    private var cacheDirURL: URL
    
    init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirURL = documentsPath.appendingPathComponent("MapTiles")
        
        if !fileManager.fileExists(atPath: cacheDirURL.path) {
            try? fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        loadRegions()
        calculateCacheSize()
    }
    
    func downloadTiles(region: MKCoordinateRegion, minZoom: Int, maxZoom: Int, completion: @escaping (UUID) -> Void) {
        guard !isDownloading else { return }
        
        let regionId = UUID()
        let downloadedRegion = DownloadedRegion(
            center: region.center,
            radiusKm: region.span.latitudeDelta * 111.0,
            name: "Downloading..."
        )
        
        DispatchQueue.main.async {
            self.downloadedRegions.append(downloadedRegion)
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.downloadedTilesCount = 0
        }
        
        let tiles = calculateTileCoordinates(for: region, minZoom: minZoom, maxZoom: maxZoom)
        totalTilesCount = tiles.count
        
        downloadTiles(tiles: tiles, regionId: regionId) { success in
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadProgress = 1.0
                
                if success {
                    if let index = self.downloadedRegions.firstIndex(where: { $0.id == regionId }) {
                        var updatedRegion = downloadedRegion
                        updatedRegion.name = "Downloaded Region"
                        self.downloadedRegions[index] = updatedRegion
                    }
                    self.saveRegions()
                    self.calculateCacheSize()
                    completion(regionId)
                } else {
                    self.downloadedRegions.removeAll { $0.id == regionId }
                }
            }
        }
    }
    
    private func calculateTileCoordinates(for region: MKCoordinateRegion, minZoom: Int, maxZoom: Int) -> [(x: Int, y: Int, z: Int)] {
        var tiles: [(x: Int, y: Int, z: Int)] = []
        
        for zoom in minZoom...maxZoom {
            let scale = pow(2.0, Double(zoom))
            
            let minLat = region.center.latitude - region.span.latitudeDelta / 2
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2
            let minLon = region.center.longitude - region.span.longitudeDelta / 2
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2
            
            let minX = Int(floor((minLon + 180.0) / 360.0 * scale))
            let maxX = Int(floor((maxLon + 180.0) / 360.0 * scale))
            
            let minY = Int(floor((1.0 - log(tan(minLat * .pi / 180.0) + 1.0 / cos(minLat * .pi / 180.0)) / .pi) / 2.0 * scale))
            let maxY = Int(floor((1.0 - log(tan(maxLat * .pi / 180.0) + 1.0 / cos(maxLat * .pi / 180.0)) / .pi) / 2.0 * scale))
            
            for x in minX...maxX {
                for y in minY...maxY {
                    tiles.append((x: x, y: y, z: zoom))
                }
            }
        }
        
        return tiles
    }
    
    private func downloadTiles(tiles: [(x: Int, y: Int, z: Int)], regionId: UUID, completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var downloadedCount = 0
        var hasError = false
        
        for tile in tiles {
            group.enter()
            downloadSingleTile(x: tile.x, y: tile.y, z: tile.z) { [weak self] success in
                defer { group.leave() }
                
                if success {
                    downloadedCount += 1
                    DispatchQueue.main.async {
                        self?.downloadedTilesCount = downloadedCount
                        self?.downloadProgress = Double(downloadedCount) / Double(tiles.count)
                    }
                } else {
                    hasError = true
                }
            }
        }
        
        group.notify(queue: .global(qos: .background)) {
            completion(!hasError)
        }
    }
    
    private func downloadSingleTile(x: Int, y: Int, z: Int, completion: @escaping (Bool) -> Void) {
        let urlString = "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        let tileDir = cacheDirURL.appendingPathComponent("\(z)/\(x)")
        let tileFile = tileDir.appendingPathComponent("\(y).png")
        
        if fileManager.fileExists(atPath: tileFile.path) {
            completion(true)
            return
        }
        
        try? fileManager.createDirectory(at: tileDir, withIntermediateDirectories: true, attributes: nil)
        
        let task = session.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(false)
                return
            }
            
            do {
                try data.write(to: tileFile)
                completion(true)
            } catch {
                completion(false)
            }
        }
        
        task.resume()
        
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        downloadProgress = 0.0
        downloadedTilesCount = 0
        totalTilesCount = 0
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirURL)
        try? fileManager.createDirectory(at: cacheDirURL, withIntermediateDirectories: true, attributes: nil)
        
        downloadedRegions.removeAll()
        cacheSize = 0
        saveRegions()
    }
    
    func deleteRegion(at index: Int) {
        guard index < downloadedRegions.count else { return }
        downloadedRegions.remove(at: index)
        saveRegions()
        calculateCacheSize()
    }
    
    func updateRegionName(id: UUID, name: String) {
        if let index = downloadedRegions.firstIndex(where: { $0.id == id }) {
            downloadedRegions[index].name = name
            downloadedRegions[index].lastUpdated = Date()
            saveRegions()
        }
    }
    
    func fetchLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let name = placemark.locality ?? 
                          placemark.subLocality ?? 
                          placemark.thoroughfare ??
                          placemark.administrativeArea ?? 
                          "Unknown Location"
                completion(name)
            } else {
                completion("Unknown Location")
            }
        }
    }
    
    private func calculateCacheSize() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let strongSelf = self else { return }
            
            let size = strongSelf.directorySize(at: strongSelf.cacheDirURL)
            
            DispatchQueue.main.async {
                strongSelf.cacheSize = size
            }
        }
    }
    
    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    private func saveRegions() {
        if let encoded = try? JSONEncoder().encode(downloadedRegions) {
            UserDefaults.standard.set(encoded, forKey: "downloadedRegions")
        }
    }
    
    private func loadRegions() {
        if let data = UserDefaults.standard.data(forKey: "downloadedRegions"),
           let decoded = try? JSONDecoder().decode([DownloadedRegion].self, from: data) {
            downloadedRegions = decoded
        }
    }
    
    var cacheSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cacheSize)
    }
}

// MARK: - Search Manager
class SearchManager: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    
    func searchForPlaces(query: String, region: MKCoordinateRegion) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                if let mapItems = response?.mapItems {
                    self?.searchResults = mapItems
                } else {
                    self?.searchResults = []
                }
            }
        }
    }
    
    func clearSearch() {
        searchResults.removeAll()
    }
}
