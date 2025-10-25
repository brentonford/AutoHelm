import SwiftUI
import CoreBluetooth
import CoreLocation
import MapKit

// MARK: - Magnetometer Calibration Model
struct MagnetometerData: Codable {
    let x: Float
    let y: Float
    let z: Float
    let minX: Float
    let minY: Float
    let minZ: Float
    let maxX: Float
    let maxY: Float
    let maxZ: Float
}

// MARK: - Arduino Navigation Status Model
struct ArduinoNavigationStatus: Codable {
    let hasGpsFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let heading: Float
    let bearing: Float
    let distance: Float
    let targetLat: Double
    let targetLon: Double
    
    var distanceText: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}

// MARK: - Bluetooth Manager
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var signalStrength: Int = 0
    @Published var connectionStatus: String = "Disconnected"
    @Published var arduinoStatus: ArduinoNavigationStatus? = nil
    @Published var magnetometerData: MagnetometerData? = nil
    @Published var isCalibrating: Bool = false
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var gpsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var calibrationCommandCharacteristic: CBCharacteristic?
    private var calibrationDataCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let characteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    private let statusCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
    private let calibrationCommandUUID = CBUUID(string: "0000FFE3-0000-1000-8000-00805F9B34FB")
    private let calibrationDataUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9B34FB")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            discoveredDevices.removeAll()
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
            connectionStatus = "Scanning..."
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        connectionStatus = "Scan stopped"
    }
    
    func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        connectionStatus = "Connecting..."
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendWaypoint(latitude: Double, longitude: Double) {
        guard let characteristic = gpsCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let dataString = String(format: "$GPS,%.6f,%.6f,0.00*\n", latitude, longitude)
        if let data = dataString.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func startCalibration() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "START_CAL"
        if let data = command.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            isCalibrating = true
        }
    }
    
    func stopCalibration() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "STOP_CAL"
        if let data = command.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            isCalibrating = false
        }
    }
    
    func saveCalibration(_ data: MagnetometerData) {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = String(format: "SAVE_CAL:%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", 
                            data.maxX, data.maxY, data.maxZ, data.minX, data.minY, data.minZ)
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
            isCalibrating = false
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStatus = "Ready"
        case .poweredOff:
            connectionStatus = "Bluetooth Off"
        case .unauthorized:
            connectionStatus = "Unauthorized"
        case .unsupported:
            connectionStatus = "Unsupported"
        default:
            connectionStatus = "Unknown"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        centralManager.stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Disconnected"
        gpsCharacteristic = nil
        statusCharacteristic = nil
        calibrationCommandCharacteristic = nil
        calibrationDataCharacteristic = nil
        arduinoStatus = nil
        magnetometerData = nil
        isCalibrating = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Connection Failed"
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID, statusCharacteristicUUID, calibrationCommandUUID, calibrationDataUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                gpsCharacteristic = characteristic
            } else if characteristic.uuid == statusCharacteristicUUID {
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == calibrationCommandUUID {
                calibrationCommandCharacteristic = characteristic
            } else if characteristic.uuid == calibrationDataUUID {
                calibrationDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        signalStrength = RSSI.intValue
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == statusCharacteristicUUID {
            guard let data = characteristic.value,
                  let jsonString = String(data: data, encoding: .utf8) else {
                return
            }
            
            if let statusData = jsonString.data(using: .utf8) {
                do {
                    let status = try JSONDecoder().decode(ArduinoNavigationStatus.self, from: statusData)
                    DispatchQueue.main.async {
                        self.arduinoStatus = status
                    }
                } catch {
                    print("Failed to decode Arduino status: \(error)")
                }
            }
        } else if characteristic.uuid == calibrationDataUUID {
            guard let data = characteristic.value,
                  let jsonString = String(data: data, encoding: .utf8) else {
                return
            }
            
            if let calibrationData = jsonString.data(using: .utf8) {
                do {
                    let magData = try JSONDecoder().decode(MagnetometerData.self, from: calibrationData)
                    DispatchQueue.main.async {
                        self.magnetometerData = magData
                    }
                } catch {
                    print("Failed to decode magnetometer data: \(error)")
                }
            }
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var accuracy: Double = 0.0
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }
        location = newLocation
        accuracy = newLocation.horizontalAccuracy
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }
}

// MARK: - Search Manager
class SearchManager: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false
    
    func searchForPlaces(query: String, region: MKCoordinateRegion) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
                if let response = response {
                    self?.searchResults = response.mapItems
                } else {
                    self?.searchResults = []
                }
            }
        }
    }
    
    func clearSearch() {
        searchResults = []
        isSearching = false
    }
}

// MARK: - Waypoint Model
struct Waypoint: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    var name: String
    var isSaved: Bool
    
    init(coordinate: CLLocationCoordinate2D, name: String = "New Waypoint", isSaved: Bool = false) {
        self.id = UUID()
        self.coordinate = coordinate
        self.timestamp = Date()
        self.name = name
        self.isSaved = isSaved
    }
    
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, timestamp, name, isSaved
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Waypoint"
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
        try container.encode(isSaved, forKey: .isSaved)
    }
}

// MARK: - Waypoint Manager
class WaypointManager: ObservableObject {
    @Published var savedWaypoints: [Waypoint] = []
    
    init() {
        loadWaypoints()
    }
    
    func saveWaypoint(_ waypoint: Waypoint) {
        var savedWaypoint = waypoint
        savedWaypoint.isSaved = true
        savedWaypoints.append(savedWaypoint)
        saveToStorage()
    }
    
    func updateWaypoint(id: UUID, name: String) {
        if let index = savedWaypoints.firstIndex(where: { $0.id == id }) {
            savedWaypoints[index].name = name
            saveToStorage()
        }
    }
    
    func deleteWaypoint(at index: Int) {
        savedWaypoints.remove(at: index)
        saveToStorage()
    }
    
    func deleteWaypoint(id: UUID) {
        savedWaypoints.removeAll { $0.id == id }
        saveToStorage()
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
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(savedWaypoints) {
            UserDefaults.standard.set(encoded, forKey: "savedWaypoints")
        }
    }
    
    private func loadWaypoints() {
        if let data = UserDefaults.standard.data(forKey: "savedWaypoints"),
           let decoded = try? JSONDecoder().decode([Waypoint].self, from: data) {
            savedWaypoints = decoded
        }
    }
}

// MARK: - Offline Tile Manager
class OfflineTileManager: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadedTilesCount: Int = 0
    @Published var totalTilesCount: Int = 0
    @Published var downloadedRegions: [DownloadedRegion] = []
    @Published var isUpdatingAll: Bool = false
    @Published var updateProgress: Double = 0.0
    
    private let fileManager = FileManager.default
    private var downloadTasks: [URLSessionDataTask] = []
    private let sixMonthsInSeconds: TimeInterval = 180 * 24 * 60 * 60
    
    var tilesDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("OSMTiles")
    }
    
    init() {
        createTilesDirectoryIfNeeded()
        loadDownloadedRegions()
        checkForAutomaticUpdates()
    }
    
    private func createTilesDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: tilesDirectory.path) {
            try? fileManager.createDirectory(at: tilesDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func checkForAutomaticUpdates() {
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? Date.distantPast
        let shouldUpdate = Date().timeIntervalSince(lastCheck) > sixMonthsInSeconds
        
        if shouldUpdate && !downloadedRegions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.updateAllMapsAutomatically()
            }
        }
    }
    
    func updateAllMaps() {
        guard !downloadedRegions.isEmpty && !isUpdatingAll else { return }
        
        isUpdatingAll = true
        updateProgress = 0.0
        let totalRegions = downloadedRegions.count
        var completedRegions = 0
        
        let group = DispatchGroup()
        
        for (index, region) in downloadedRegions.enumerated() {
            group.enter()
            
            let kmToDegrees = region.radiusKm / 111.0
            let mapRegion = MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(latitudeDelta: kmToDegrees, longitudeDelta: kmToDegrees)
            )
            
            downloadTiles(region: mapRegion, minZoom: 10, maxZoom: 15, isUpdate: true) { regionId in
                completedRegions += 1
                DispatchQueue.main.async {
                    self.updateProgress = Double(completedRegions) / Double(totalRegions)
                    if let regionIndex = self.downloadedRegions.firstIndex(where: { $0.id == region.id }) {
                        self.downloadedRegions[regionIndex].lastUpdated = Date()
                    }
                    self.saveDownloadedRegions()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.isUpdatingAll = false
            self.updateProgress = 1.0
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateProgress = 0.0
            }
        }
    }
    
    private func updateAllMapsAutomatically() {
        let regionsNeedingUpdate = downloadedRegions.filter { region in
            let timeSinceUpdate = Date().timeIntervalSince(region.lastUpdated)
            return timeSinceUpdate > sixMonthsInSeconds
        }
        
        guard !regionsNeedingUpdate.isEmpty else {
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            return
        }
        
        updateAllMaps()
    }
    
    func downloadTiles(region: MKCoordinateRegion, minZoom: Int, maxZoom: Int, isUpdate: Bool = false, completion: @escaping (UUID) -> Void) {
        if !isUpdate {
            isDownloading = true
            downloadProgress = 0.0
            downloadedTilesCount = 0
        }
        
        let tiles = calculateTiles(for: region, minZoom: minZoom, maxZoom: maxZoom)
        totalTilesCount = tiles.count
        
        var regionId: UUID
        if isUpdate {
            regionId = UUID()
        } else {
            let newRegion = DownloadedRegion(
                center: region.center,
                radiusKm: regionSpanToKm(span: region.span),
                name: "Loading..."
            )
            regionId = newRegion.id
            downloadedRegions.append(newRegion)
            saveDownloadedRegions()
        }
        
        let group = DispatchGroup()
        
        for tile in tiles {
            group.enter()
            downloadTile(z: tile.z, x: tile.x, y: tile.y) { success in
                DispatchQueue.main.async {
                    if success && !isUpdate {
                        self.downloadedTilesCount += 1
                        self.downloadProgress = Double(self.downloadedTilesCount) / Double(self.totalTilesCount)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            if !isUpdate {
                self.isDownloading = false
                self.downloadProgress = 1.0
            }
            completion(regionId)
        }
    }
    
    func updateRegionName(id: UUID, name: String) {
        if let index = downloadedRegions.firstIndex(where: { $0.id == id }) {
            downloadedRegions[index].name = name
            saveDownloadedRegions()
        }
    }
    
    func fetchLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let name = placemark.locality ?? placemark.subLocality ?? placemark.administrativeArea ?? "Unknown Location"
                completion(name)
            } else {
                completion("Unknown Location")
            }
        }
    }
    
    private func regionSpanToKm(span: MKCoordinateSpan) -> Double {
        return span.latitudeDelta * 111.0
    }
    
    private func calculateTiles(for region: MKCoordinateRegion, minZoom: Int, maxZoom: Int) -> [(z: Int, x: Int, y: Int)] {
        var tiles: [(z: Int, x: Int, y: Int)] = []
        
        for zoom in minZoom...maxZoom {
            let minTile = latLonToTile(lat: region.center.latitude + region.span.latitudeDelta / 2,
                                       lon: region.center.longitude - region.span.longitudeDelta / 2,
                                       zoom: zoom)
            let maxTile = latLonToTile(lat: region.center.latitude - region.span.latitudeDelta / 2,
                                       lon: region.center.longitude + region.span.longitudeDelta / 2,
                                       zoom: zoom)
            
            for x in minTile.x...maxTile.x {
                for y in minTile.y...maxTile.y {
                    tiles.append((z: zoom, x: x, y: y))
                }
            }
        }
        
        return tiles
    }
    
    private func latLonToTile(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int((lon + 180.0) / 360.0 * n)
        let y = Int((1.0 - log(tan(lat * .pi / 180.0) + 1.0 / cos(lat * .pi / 180.0)) / .pi) / 2.0 * n)
        return (x: x, y: y)
    }
    
    private func downloadTile(z: Int, x: Int, y: Int, completion: @escaping (Bool) -> Void) {
        let tilePath = tilePath(z: z, x: x, y: y)
        
        let urlString = "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("WaypointNavigator/1.0", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(false)
                return
            }
            
            let zPath = self.tilesDirectory.appendingPathComponent("\(z)")
            let xPath = zPath.appendingPathComponent("\(x)")
            
            try? self.fileManager.createDirectory(at: zPath, withIntermediateDirectories: true)
            try? self.fileManager.createDirectory(at: xPath, withIntermediateDirectories: true)
            
            do {
                try data.write(to: tilePath)
                completion(true)
            } catch {
                completion(false)
            }
        }
        
        task.resume()
        downloadTasks.append(task)
    }
    
    private func tilePath(z: Int, x: Int, y: Int) -> URL {
        return tilesDirectory
            .appendingPathComponent("\(z)")
            .appendingPathComponent("\(x)")
            .appendingPathComponent("\(y).png")
    }
    
    func cancelDownload() {
        downloadTasks.forEach { $0.cancel() }
        downloadTasks.removeAll()
        isDownloading = false
        isUpdatingAll = false
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: tilesDirectory)
        createTilesDirectoryIfNeeded()
        downloadedTilesCount = 0
        totalTilesCount = 0
        downloadProgress = 0.0
        downloadedRegions.removeAll()
        saveDownloadedRegions()
    }
    
    func deleteRegion(at index: Int) {
        downloadedRegions.remove(at: index)
        saveDownloadedRegions()
    }
    
    func getCacheSize() -> String {
        guard let enumerator = fileManager.enumerator(at: tilesDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 MB"
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        let mbSize = Double(totalSize) / 1_048_576.0
        return String(format: "%.2f MB", mbSize)
    }
    
    private func saveDownloadedRegions() {
        if let encoded = try? JSONEncoder().encode(downloadedRegions) {
            UserDefaults.standard.set(encoded, forKey: "downloadedRegions")
        }
    }
    
    private func loadDownloadedRegions() {
        if let data = UserDefaults.standard.data(forKey: "downloadedRegions"),
           let decoded = try? JSONDecoder().decode([DownloadedRegion].self, from: data) {
            downloadedRegions = decoded
        }
    }
}

// MARK: - Downloaded Region Model
struct DownloadedRegion: Identifiable, Codable {
    let id: UUID
    let center: CLLocationCoordinate2D
    let radiusKm: Double
    let downloadDate: Date
    var lastUpdated: Date
    var name: String
    
    init(center: CLLocationCoordinate2D, radiusKm: Double, name: String = "Unnamed Region") {
        self.id = UUID()
        self.center = center
        self.radiusKm = radiusKm
        self.downloadDate = Date()
        self.lastUpdated = Date()
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case id, centerLat, centerLon, radiusKm, downloadDate, lastUpdated, name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .centerLat)
        let lon = try container.decode(Double.self, forKey: .centerLon)
        center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        radiusKm = try container.decode(Double.self, forKey: .radiusKm)
        downloadDate = try container.decode(Date.self, forKey: .downloadDate)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? downloadDate
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Region"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center.latitude, forKey: .centerLat)
        try container.encode(center.longitude, forKey: .centerLon)
        try container.encode(radiusKm, forKey: .radiusKm)
        try container.encode(downloadDate, forKey: .downloadDate)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(name, forKey: .name)
    }
}

// MARK: - Offline Tile Overlay
class OfflineTileOverlay: MKTileOverlay {
    private let offlineManager: OfflineTileManager
    
    init(offlineManager: OfflineTileManager) {
        self.offlineManager = offlineManager
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = true
    }
    
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let tilePath = offlineManager.tilesDirectory
            .appendingPathComponent("\(path.z)")
            .appendingPathComponent("\(path.x)")
            .appendingPathComponent("\(path.y).png")
        
        if FileManager.default.fileExists(atPath: tilePath.path) {
            return tilePath
        }
        
        let urlString = "https://tile.openstreetmap.org/\(path.z)/\(path.x)/\(path.y).png"
        return URL(string: urlString)!
    }
}

// MARK: - Main App
@main
struct WaypointApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var offlineTileManager = OfflineTileManager()
    @StateObject private var waypointManager = WaypointManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WaypointMapView(locationManager: locationManager, bluetoothManager: bluetoothManager, waypointManager: waypointManager)
                .tabItem {
                    Label("Waypoint", systemImage: "map.fill")
                }
                .tag(0)
            
            CombinedStatusView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(1)
            
            CalibrationView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Calibration", systemImage: "gyroscope")
                }
                .tag(2)
            
            OfflineMapsView(locationManager: locationManager, offlineTileManager: offlineTileManager)
                .tabItem {
                    Label("Offline", systemImage: "arrow.down.circle.fill")
                }
                .tag(3)
        }
        .onAppear {
            locationManager.requestAuthorization()
        }
    }
}

// MARK: - Combined Status View
struct CombinedStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isConnectionSectionExpanded = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Connection")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        
                        if bluetoothManager.isConnected {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text("(\(bluetoothManager.signalStrength) dBm)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isConnectionSectionExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isConnectionSectionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    if isConnectionSectionExpanded || !bluetoothManager.isConnected {
                        ConnectionSectionView(bluetoothManager: bluetoothManager)
                            .padding(.horizontal, 8)
                    }
                }
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                
                if bluetoothManager.isConnected {
                    if let status = bluetoothManager.arduinoStatus {
                        ScrollView {
                            VStack(spacing: 12) {
                                NavigationStatusCard(status: status)
                                GPSStatusCard(status: status)
                                TargetStatusCard(status: status)
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "clock")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("Waiting for Arduino data...")
                                .font(.callout)
                                .foregroundColor(.gray)
                            Text("Make sure the Arduino is powered on and GPS has a fix")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Arduino not connected")
                            .font(.callout)
                            .foregroundColor(.red)
                        Text("Use the connection controls above to establish connection")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    Spacer()
                }
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Connection Section View
struct ConnectionSectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 12) {
            if bluetoothManager.isConnected {
                Button(action: {
                    bluetoothManager.disconnect()
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        Text("Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            } else {
                if !bluetoothManager.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Available Devices")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                            Button(action: {
                                bluetoothManager.connect(to: device)
                            }) {
                                HStack {
                                    Image(systemName: "sensor")
                                        .foregroundColor(.blue)
                                    Text(device.name ?? "Unknown Device")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                HStack(spacing: 10) {
                    Button(action: {
                        bluetoothManager.startScanning()
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Scan")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    
                    Button(action: {
                        bluetoothManager.stopScanning()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("Stop")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}

// MARK: - Waypoint Map View
struct WaypointMapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    @StateObject private var searchManager = SearchManager()
    
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedWaypoint: Waypoint?
    @State private var showConfirmation = false
    @State private var showSavedWaypoints = false
    @State private var editingWaypointId: UUID?
    @State private var editingWaypointName: String = ""
    @State private var hasSetInitialPosition = false
    @State private var searchText = ""
    @State private var showSearchResults = false
    @State private var mapStyle: MKMapType = .satellite
    @State private var showMapStylePicker = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position) {
                        UserAnnotation()
                        
                        ForEach(waypointManager.savedWaypoints) { waypoint in
                            Annotation("", coordinate: waypoint.coordinate) {
                                VStack(spacing: 0) {
                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.yellow)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                    Text(waypoint.name)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.yellow.opacity(0.8))
                                        .cornerRadius(4)
                                }
                                .onTapGesture {
                                    selectedWaypoint = waypoint
                                }
                            }
                        }
                        
                        ForEach(searchManager.searchResults, id: \.self) { item in
                            if let coordinate = item.placemark.location?.coordinate {
                                Annotation("", coordinate: coordinate) {
                                    VStack(spacing: 0) {
                                        Image(systemName: "magnifyingglass.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.blue)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                        Text(item.name ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.8))
                                            .cornerRadius(4)
                                    }
                                    .onTapGesture {
                                        let waypoint = Waypoint(coordinate: coordinate, name: item.name ?? "Search Result")
                                        selectedWaypoint = waypoint
                                        searchManager.clearSearch()
                                        searchText = ""
                                        showSearchResults = false
                                    }
                                }
                            }
                        }
                        
                        if let waypoint = selectedWaypoint, !waypoint.isSaved {
                            Annotation("", coordinate: waypoint.coordinate) {
                                VStack(spacing: 0) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.red)
                                    Image(systemName: "arrowtriangle.down.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                        .offset(y: -5)
                                }
                            }
                        }
                    }
                    .mapStyle(mapStyle == .standard ? .standard : .hybrid)
                    .onTapGesture { screenCoordinate in
                        if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                            waypointManager.fetchLocationName(for: coordinate) { locationName in
                                let waypoint = Waypoint(coordinate: coordinate, name: locationName)
                                selectedWaypoint = waypoint
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if showSearchResults && !searchManager.searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(searchManager.searchResults.prefix(5)), id: \.self) { item in
                                Button(action: {
                                    if let coordinate = item.placemark.location?.coordinate {
                                        position = .region(MKCoordinateRegion(
                                            center: coordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                        ))
                                        let waypoint = Waypoint(coordinate: coordinate, name: item.name ?? "Search Result")
                                        selectedWaypoint = waypoint
                                        searchManager.clearSearch()
                                        searchText = ""
                                        showSearchResults = false
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "Unknown")
                                                .foregroundColor(.primary)
                                                .font(.subheadline)
                                            if let address = item.placemark.title {
                                                Text(address)
                                                    .foregroundColor(.gray)
                                                    .font(.caption)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                Divider()
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
                        .shadow(radius: 2)
                        .padding(.horizontal, 12)
                    }
                    
                    Spacer()
                    
                    if let waypoint = selectedWaypoint {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    if waypoint.isSaved {
                                        Text(waypoint.name)
                                            .font(.callout)
                                            .fontWeight(.medium)
                                    } else {
                                        Text("Selected Waypoint")
                                            .font(.callout)
                                            .fontWeight(.medium)
                                    }
                                    Text("Lat: \(waypoint.coordinate.latitude, specifier: "%.6f")")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("Lon: \(waypoint.coordinate.longitude, specifier: "%.6f")")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                Spacer()
                                Button(action: {
                                    selectedWaypoint = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            if waypoint.isSaved {
                                HStack(spacing: 8) {
                                    if bluetoothManager.isConnected {
                                        Button(action: {
                                            bluetoothManager.sendWaypoint(
                                                latitude: waypoint.coordinate.latitude,
                                                longitude: waypoint.coordinate.longitude
                                            )
                                            showConfirmation = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                showConfirmation = false
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "paperplane.fill")
                                                Text("Send")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                    
                                    Button(action: {
                                        waypointManager.deleteWaypoint(id: waypoint.id)
                                        selectedWaypoint = nil
                                    }) {
                                        HStack {
                                            Image(systemName: "trash.fill")
                                            Text("Delete")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    if bluetoothManager.isConnected {
                                        Button(action: {
                                            bluetoothManager.sendWaypoint(
                                                latitude: waypoint.coordinate.latitude,
                                                longitude: waypoint.coordinate.longitude
                                            )
                                            showConfirmation = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                showConfirmation = false
                                            }
                                        }) {
                                            HStack {
                                                Image(systemName: "paperplane.fill")
                                                Text("Send to Arduino")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                    
                                    Button(action: {
                                        waypointManager.saveWaypoint(waypoint)
                                        selectedWaypoint = waypointManager.savedWaypoints.last
                                    }) {
                                        HStack {
                                            Image(systemName: "star.fill")
                                            Text("Save Waypoint")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            
                            if !bluetoothManager.isConnected && !waypoint.isSaved {
                                Text("Connect to Arduino to send waypoint")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .italic()
                            }
                            
                            if showConfirmation {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Waypoint sent!")
                                        .font(.subheadline)
                                }
                                .padding(6)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 8)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.tap.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("Tap anywhere on the map to set a waypoint")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 8)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button(action: {
                            showSavedWaypoints.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                Text("\(waypointManager.savedWaypoints.count)")
                            }
                            .font(.caption)
                        }
                        
                        Button(action: {
                            showMapStylePicker.toggle()
                        }) {
                            Image(systemName: mapStyle == .standard ? "map" : "globe.europe.africa")
                                .font(.caption)
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.caption)
                        
                        TextField("Search places...", text: $searchText, onEditingChanged: { isEditing in
                            showSearchResults = isEditing && !searchText.isEmpty
                        })
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.subheadline)
                        .onSubmit {
                            if let region = getCurrentMapRegion() {
                                searchManager.searchForPlaces(query: searchText, region: region)
                                showSearchResults = true
                            }
                        }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchManager.clearSearch()
                                showSearchResults = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let location = locationManager.location {
                            position = .region(MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                    }
                }
            }
            .sheet(isPresented: $showSavedWaypoints) {
                SavedWaypointsView(waypointManager: waypointManager, bluetoothManager: bluetoothManager, selectedWaypoint: $selectedWaypoint, showSheet: $showSavedWaypoints)
            }
            .actionSheet(isPresented: $showMapStylePicker) {
                ActionSheet(
                    title: Text("Map Style"),
                    buttons: [
                        .default(Text("Standard")) {
                            mapStyle = .standard
                        },
                        .default(Text("Satellite")) {
                            mapStyle = .satellite
                        },
                        .cancel()
                    ]
                )
            }
        }
        .onChange(of: locationManager.location) { oldValue, newLocation in
            if let location = newLocation, !hasSetInitialPosition {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                hasSetInitialPosition = true
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if newValue.isEmpty {
                searchManager.clearSearch()
                showSearchResults = false
            } else if newValue.count > 2 {
                if let region = getCurrentMapRegion() {
                    searchManager.searchForPlaces(query: newValue, region: region)
                    showSearchResults = true
                }
            }
        }
    }
    
    private func getCurrentMapRegion() -> MKCoordinateRegion? {
        if let location = locationManager.location {
            return MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return nil
    }
}

// MARK: - Saved Waypoints View
struct SavedWaypointsView: View {
    @ObservedObject var waypointManager: WaypointManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var selectedWaypoint: Waypoint?
    @Binding var showSheet: Bool
    @State private var editingWaypointId: UUID?
    @State private var editingWaypointName: String = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(waypointManager.savedWaypoints.enumerated()), id: \.element.id) { index, waypoint in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                if editingWaypointId == waypoint.id {
                                    TextField("Waypoint name", text: $editingWaypointName, onCommit: {
                                        waypointManager.updateWaypoint(id: waypoint.id, name: editingWaypointName)
                                        editingWaypointId = nil
                                    })
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                } else {
                                    Text(waypoint.name)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                }
                                Text("Lat: \(waypoint.coordinate.latitude, specifier: "%.6f")")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.gray)
                                Text("Lon: \(waypoint.coordinate.longitude, specifier: "%.6f")")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            if editingWaypointId != waypoint.id {
                                Button(action: {
                                    editingWaypointId = waypoint.id
                                    editingWaypointName = waypoint.name
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                selectedWaypoint = waypoint
                                showSheet = false
                            }) {
                                HStack {
                                    Image(systemName: "map")
                                    Text("View")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            if bluetoothManager.isConnected {
                                Button(action: {
                                    bluetoothManager.sendWaypoint(
                                        latitude: waypoint.coordinate.latitude,
                                        longitude: waypoint.coordinate.longitude
                                    )
                                }) {
                                    HStack {
                                        Image(systemName: "paperplane.fill")
                                        Text("Send")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            Button(action: {
                                waypointManager.deleteWaypoint(at: index)
                                if selectedWaypoint?.id == waypoint.id {
                                    selectedWaypoint = nil
                                }
                                if editingWaypointId == waypoint.id {
                                    editingWaypointId = nil
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Saved Waypoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSheet = false
                    }
                }
            }
        }
    }
}

// MARK: - Offline Maps View
struct OfflineMapsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @State private var position: MapCameraPosition = .automatic
    @State private var radiusKm: Double = 5.0
    @State private var selectedCenter: CLLocationCoordinate2D?
    @State private var showDownloadAlert = false
    @State private var editingRegionId: UUID?
    @State private var editingRegionName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    MapReader { proxy in
                        Map(position: $position) {
                            UserAnnotation()
                            
                            ForEach(offlineTileManager.downloadedRegions) { region in
                                MapCircle(center: region.center, radius: region.radiusKm * 1000)
                                    .foregroundStyle(Color.green.opacity(0.2))
                                    .stroke(Color.green, lineWidth: 2)
                                
                                Annotation("", coordinate: region.center) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.green)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                        Text(region.name)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.green)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            
                            if let center = selectedCenter {
                                MapCircle(center: center, radius: radiusKm * 1000)
                                    .foregroundStyle(Color.blue.opacity(0.2))
                                    .stroke(Color.blue, lineWidth: 2)
                                
                                Annotation("", coordinate: center) {
                                    VStack(spacing: 2) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.title)
                                                .foregroundColor(.blue)
                                        }
                                        Text("\(radiusKm, specifier: "%.1f") km")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.blue)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                                }
                                .mapStyle(.hybrid)
                                .frame(height: 300)
                                .onTapGesture { screenCoordinate in
                            if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                                selectedCenter = coordinate
                            }
                        }
                    }
                    
                    if selectedCenter == nil && offlineTileManager.downloadedRegions.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: "hand.tap.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text("Tap map to select download area")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding()
                    }
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        if let center = selectedCenter {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Selected Location")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text("Lat: \(center.latitude, specifier: "%.6f")")
                                    .font(.system(.caption, design: .monospaced))
                                Text("Lon: \(center.longitude, specifier: "%.6f")")
                                    .font(.system(.caption, design: .monospaced))
                                
                                Button(action: {
                                    selectedCenter = nil
                                }) {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                        Text("Clear Selection")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal, 12)
                        }
                        
                        if !offlineTileManager.downloadedRegions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Downloaded Regions")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if !offlineTileManager.isUpdatingAll && !offlineTileManager.isDownloading {
                                        Button(action: {
                                            offlineTileManager.updateAllMaps()
                                        }) {
                                            HStack {
                                                Image(systemName: "arrow.clockwise")
                                                Text("Update All")
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                                
                                if offlineTileManager.isUpdatingAll {
                                    VStack(spacing: 6) {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                                .foregroundColor(.blue)
                                            Text("Updating all maps...")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Spacer()
                                        }
                                        ProgressView(value: offlineTileManager.updateProgress)
                                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    }
                                    .padding(8)
                                    .background(Color.blue.opacity(0.08))
                                    .cornerRadius(6)
                                }
                                
                                ForEach(Array(offlineTileManager.downloadedRegions.enumerated()), id: \.element.id) { index, region in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            if editingRegionId == region.id {
                                                TextField("Region name", text: $editingRegionName, onCommit: {
                                                    offlineTileManager.updateRegionName(id: region.id, name: editingRegionName)
                                                    editingRegionId = nil
                                                })
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                            } else {
                                                Text(region.name)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            Text("Radius: \(region.radiusKm, specifier: "%.1f") km")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                            Text("Downloaded: \(region.downloadDate, style: .date)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                            if region.lastUpdated != region.downloadDate {
                                                Text("Last Updated: \(region.lastUpdated, style: .date)")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        Spacer()
                                        if editingRegionId != region.id {
                                            Button(action: {
                                                editingRegionId = region.id
                                                editingRegionName = region.name
                                            }) {
                                                Image(systemName: "pencil")
                                                    .foregroundColor(.blue)
                                                    .font(.caption)
                                            }
                                            .padding(.trailing, 6)
                                        }
                                        Button(action: {
                                            offlineTileManager.deleteRegion(at: index)
                                            if editingRegionId == region.id {
                                                editingRegionId = nil
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.green.opacity(0.08))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(12)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal, 12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cache Information")
                                .font(.callout)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Cache Size:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(offlineTileManager.getCacheSize())
                                    .font(.system(.callout, design: .monospaced))
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Download Radius: \(radiusKm, specifier: "%.1f") km")
                                .font(.callout)
                                .fontWeight(.medium)
                            
                            Slider(value: $radiusKm, in: 1.0...20.0, step: 1.0)
                            
                            Text("Larger areas require more storage and time")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        
                        if offlineTileManager.isDownloading {
                            VStack(spacing: 8) {
                                ProgressView(value: offlineTileManager.downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                
                                Text("\(offlineTileManager.downloadedTilesCount) / \(offlineTileManager.totalTilesCount) tiles")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Button(action: {
                                    offlineTileManager.cancelDownload()
                                }) {
                                    Text("Cancel Download")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(12)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal, 12)
                        } else {
                            Button(action: {
                                showDownloadAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download Maps for Selected Area")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedCenter != nil ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(selectedCenter == nil)
                            .padding(.horizontal, 12)
                        }
                        
                        Button(action: {
                            offlineTileManager.clearCache()
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear All Cached Maps")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 12)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Information")
                                .font(.callout)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Tap the map to select download location")
                                    .font(.caption)
                                Text("• Blue circle shows selected download area")
                                    .font(.caption)
                                Text("• Green circles show downloaded regions")
                                    .font(.caption)
                                Text("• Tap pencil icon to rename a region")
                                    .font(.caption)
                                Text("• Use 'Update All' to refresh downloaded maps")
                                    .font(.caption)
                                Text("• Maps automatically update every 6 months")
                                    .font(.caption)
                                Text("• Maps are downloaded from OpenStreetMap")
                                    .font(.caption)
                                Text("• Downloaded maps work without internet")
                                    .font(.caption)
                                Text("• Zoom levels 10-15 are downloaded")
                                    .font(.caption)
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Offline Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let location = locationManager.location {
                            position = .region(MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                            ))
                        }
                    }) {
                        Image(systemName: "location.fill")
                    }
                }
            }
            .alert("Download Maps", isPresented: $showDownloadAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Download") {
                    if let center = selectedCenter {
                        let kmToDegrees = radiusKm / 111.0
                        let region = MKCoordinateRegion(
                            center: center,
                            span: MKCoordinateSpan(latitudeDelta: kmToDegrees, longitudeDelta: kmToDegrees)
                        )
                        offlineTileManager.downloadTiles(region: region, minZoom: 10, maxZoom: 15) { regionId in
                            offlineTileManager.fetchLocationName(for: center) { locationName in
                                offlineTileManager.updateRegionName(id: regionId, name: locationName)
                            }
                        }
                        selectedCenter = nil
                    }
                }
            } message: {
                Text("Download maps for \(radiusKm, specifier: "%.1f") km radius around selected location? This may take several minutes.")
            }
        }
        .onChange(of: locationManager.location) { oldValue, newLocation in
            if let location = newLocation, selectedCenter == nil, offlineTileManager.downloadedRegions.isEmpty {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                ))
            }
        }
    }
}

// MARK: - Status Cards
struct NavigationStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navigation")
                .font(.callout)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "location.north.fill")
                            .foregroundColor(.blue)
                        Text("Heading: \(status.heading, specifier: "%.1f")°")
                            .font(.caption)
                    }
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundColor(.green)
                        Text("Bearing: \(status.bearing, specifier: "%.1f")°")
                            .font(.caption)
                    }
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(.orange)
                        Text("Distance: \(status.distanceText)")
                            .font(.caption)
                    }
                }
                Spacer()
                EnhancedCompassView(heading: status.heading, bearing: status.bearing)
                    .frame(width: 80, height: 80)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}

struct GPSStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPS Status")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                Circle()
                    .fill(status.hasGpsFix ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(status.hasGpsFix ? "Fix" : "No Fix")
                    .font(.caption)
                    .foregroundColor(status.hasGpsFix ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "dot.radiowaves.up")
                        .foregroundColor(.blue)
                    Text("Satellites: \(status.satellites)")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Lat: \(status.currentLat, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("Lon: \(status.currentLon, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "mountain.2.fill")
                        .foregroundColor(.brown)
                    Text("Alt: \(status.altitude, specifier: "%.1f") m")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(status.hasGpsFix ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

struct TargetStatusCard: View {
    let status: ArduinoNavigationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Waypoint")
                .font(.callout)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text("Lat: \(status.targetLat, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text("Lon: \(status.targetLon, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

struct EnhancedCompassView: View {
    let heading: Float
    let bearing: Float
    @State private var animatedHeading: Double = 0
    @State private var animatedBearing: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.1)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            ForEach(0..<8) { i in
                let angle = Double(i) * 45
                VStack {
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.black : Color.gray)
                        .frame(width: i % 2 == 0 ? 1.5 : 1, height: i % 2 == 0 ? 8 : 6)
                    Spacer()
                }
                .rotationEffect(.degrees(angle))
            }
            
            VStack {
                Text("N")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
            }
            
            Group {
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 40))
                    let endX = 40 + 28 * sin(animatedHeading * .pi / 180)
                    let endY = 40 - 28 * cos(animatedHeading * .pi / 180)
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Color.blue.opacity(0.3), radius: 1, x: 0, y: 1)
                
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 40))
                    let endX = 40 + 20 * sin(animatedBearing * .pi / 180)
                    let endY = 40 - 20 * cos(animatedBearing * .pi / 180)
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: Color.red.opacity(0.3), radius: 1, x: 0, y: 1)
            }
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white, Color.black]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 3
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
        .onAppear {
            animatedHeading = Double(heading)
            animatedBearing = Double(bearing)
        }
        .onChange(of: heading) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedHeading = Double(newValue)
            }
        }
        .onChange(of: bearing) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedBearing = Double(newValue)
            }
        }
    }
}

// MARK: - Calibration View
struct CalibrationView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showCalibrationComplete = false
    @State private var currentStep = 1
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if !bluetoothManager.isConnected {
                        VStack(spacing: 16) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.red)
                            Text("Connect to Helm Device")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("Please connect to your Helm device in the Status tab before calibrating the magnetometer.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 16) {
                            Text("Magnetometer Calibration")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Follow these steps to calibrate your compass for accurate navigation.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        if !bluetoothManager.isCalibrating {
                            CalibrationInstructions()
                            
                            Button(action: {
                                bluetoothManager.startCalibration()
                                currentStep = 1
                            }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("Start Calibration")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        } else {
                            CalibrationActiveView(
                                magnetometerData: bluetoothManager.magnetometerData,
                                onSave: { data in
                                    bluetoothManager.saveCalibration(data)
                                    showCalibrationComplete = true
                                },
                                onDiscard: {
                                    bluetoothManager.stopCalibration()
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Compass")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Calibration Complete", isPresented: $showCalibrationComplete) {
            Button("OK") {
                showCalibrationComplete = false
            }
        } message: {
            Text("Magnetometer calibration has been saved to the Helm device. Your compass should now be more accurate.")
        }
    }
}

struct CalibrationInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibration Steps:")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 12) {
                CalibrationStep(number: 1, text: "Tap 'Start Calibration' to begin")
                CalibrationStep(number: 2, text: "Hold the Helm device steady")
                CalibrationStep(number: 3, text: "Slowly rotate the device in all directions")
                CalibrationStep(number: 4, text: "Continue for 60-90 seconds")
                CalibrationStep(number: 5, text: "Tap 'Save' when readings stabilize")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Important Tips:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                
                Text("• Stay away from metal objects and electronics")
                    .font(.caption)
                Text("• Rotate slowly and smoothly in figure-8 patterns")
                    .font(.caption)
                Text("• Ensure all axes (X, Y, Z) show movement")
                    .font(.caption)
                Text("• Calibrate outdoors for best results")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct CalibrationStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}

struct CalibrationActiveView: View {
    let magnetometerData: MagnetometerData?
    let onSave: (MagnetometerData) -> Void
    let onDiscard: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Calibration in Progress")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Rotate the Helm device slowly in all directions")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let data = magnetometerData {
                VStack(spacing: 16) {
                    MagnetometerReadingsView(data: data)
                    CalibrationProgressView(data: data)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button(action: onDiscard) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Discard")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: { onSave(data) }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("Waiting for magnetometer data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct MagnetometerReadingsView: View {
    let data: MagnetometerData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Readings")
                .font(.headline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("X: \(data.x, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                    Text("Y: \(data.y, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                    Text("Z: \(data.z, specifier: "%.1f")")
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Range X: \(data.maxX - data.minX, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Range Y: \(data.maxY - data.minY, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Range Z: \(data.maxZ - data.minZ, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CalibrationProgressView: View {
    let data: MagnetometerData
    
    private var progress: Double {
        let rangeX = data.maxX - data.minX
        let rangeY = data.maxY - data.minY
        let rangeZ = data.maxZ - data.minZ
        let avgRange = (rangeX + rangeY + rangeZ) / 3.0
        return min(Double(avgRange) / 100.0, 1.0)
    }
    
    private var isCalibrationGood: Bool {
        progress > 0.7
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calibration Progress")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                if isCalibrationGood {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: isCalibrationGood ? .green : .blue))
            
            Text(isCalibrationGood ? "Ready to save calibration" : "Keep rotating in all directions")
                .font(.caption)
                .foregroundColor(isCalibrationGood ? .green : .secondary)
        }
    }
}

// MARK: - Helper Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}