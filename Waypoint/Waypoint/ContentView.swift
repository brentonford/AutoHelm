import SwiftUI
import CoreBluetooth
import CoreLocation
import MapKit

// MARK: - Offline Tile Manager
class OfflineTileManager: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadedTilesCount: Int = 0
    @Published var totalTilesCount: Int = 0
    @Published var downloadedRegions: [DownloadedRegion] = []
    
    private let fileManager = FileManager.default
    private var downloadTasks: [URLSessionDataTask] = []
    
    var tilesDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("OSMTiles")
    }
    
    init() {
        createTilesDirectoryIfNeeded()
        loadDownloadedRegions()
    }
    
    private func createTilesDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: tilesDirectory.path) {
            try? fileManager.createDirectory(at: tilesDirectory, withIntermediateDirectories: true)
        }
    }
    
    func downloadTiles(region: MKCoordinateRegion, minZoom: Int, maxZoom: Int, completion: @escaping (UUID) -> Void) {
        isDownloading = true
        downloadProgress = 0.0
        downloadedTilesCount = 0
        
        let tiles = calculateTiles(for: region, minZoom: minZoom, maxZoom: maxZoom)
        totalTilesCount = tiles.count
        
        let newRegion = DownloadedRegion(
            center: region.center,
            radiusKm: regionSpanToKm(span: region.span),
            name: "Loading..."
        )
        let regionId = newRegion.id
        downloadedRegions.append(newRegion)
        saveDownloadedRegions()
        
        let group = DispatchGroup()
        
        for tile in tiles {
            group.enter()
            downloadTile(z: tile.z, x: tile.x, y: tile.y) { success in
                DispatchQueue.main.async {
                    if success {
                        self.downloadedTilesCount += 1
                        self.downloadProgress = Double(self.downloadedTilesCount) / Double(self.totalTilesCount)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            self.isDownloading = false
            self.downloadProgress = 1.0
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
        
        if fileManager.fileExists(atPath: tilePath.path) {
            completion(true)
            return
        }
        
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
    var name: String
    
    init(center: CLLocationCoordinate2D, radiusKm: Double, name: String = "Unnamed Region") {
        self.id = UUID()
        self.center = center
        self.radiusKm = radiusKm
        self.downloadDate = Date()
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case id, centerLat, centerLon, radiusKm, downloadDate, name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .centerLat)
        let lon = try container.decode(Double.self, forKey: .centerLon)
        center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        radiusKm = try container.decode(Double.self, forKey: .radiusKm)
        downloadDate = try container.decode(Date.self, forKey: .downloadDate)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Region"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center.latitude, forKey: .centerLat)
        try container.encode(center.longitude, forKey: .centerLon)
        try container.encode(radiusKm, forKey: .radiusKm)
        try container.encode(downloadDate, forKey: .downloadDate)
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

// MARK: - Bluetooth Manager
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var signalStrength: Int = 0
    @Published var connectionStatus: String = "Disconnected"
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var gpsCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let characteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    
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
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                gpsCharacteristic = characteristic
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        signalStrength = RSSI.intValue
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
            ConnectionView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)
            
            WaypointMapView(locationManager: locationManager, bluetoothManager: bluetoothManager, waypointManager: waypointManager)
                .tabItem {
                    Label("Waypoint", systemImage: "map.fill")
                }
                .tag(1)
            
            OfflineMapsView(locationManager: locationManager, offlineTileManager: offlineTileManager)
                .tabItem {
                    Label("Offline", systemImage: "arrow.down.circle.fill")
                }
                .tag(2)
        }
        .onAppear {
            locationManager.requestAuthorization()
        }
    }
}

// MARK: - Connection View
struct ConnectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                StatusCard(title: "Status", value: bluetoothManager.connectionStatus, color: bluetoothManager.isConnected ? .green : .gray)
                
                if bluetoothManager.isConnected {
                    StatusCard(title: "Signal", value: "\(bluetoothManager.signalStrength) dBm", color: .blue)
                    
                    Button(action: {
                        bluetoothManager.disconnect()
                    }) {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                } else {
                    List(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                        Button(action: {
                            bluetoothManager.connect(to: device)
                        }) {
                            HStack {
                                Image(systemName: "sensor")
                                Text(device.name ?? "Unknown Device")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    HStack(spacing: 15) {
                        Button(action: {
                            bluetoothManager.startScanning()
                        }) {
                            Text("Scan")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        Button(action: {
                            bluetoothManager.stopScanning()
                        }) {
                            Text("Stop")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Connection")
        }
    }
}

// MARK: - Waypoint Map View
struct WaypointMapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedWaypoint: Waypoint?
    @State private var showConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position) {
                        UserAnnotation()
                        
                        if let waypoint = selectedWaypoint {
                            Annotation("Waypoint", coordinate: waypoint.coordinate) {
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
                    .onTapGesture { screenCoordinate in
                        if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                            selectedWaypoint = Waypoint(coordinate: coordinate, timestamp: Date())
                        }
                    }
                }
                .ignoresSafeArea()
                
                VStack(spacing: 15) {
                    if let waypoint = selectedWaypoint {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Selected Waypoint")
                                        .font(.headline)
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
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                }
                            }
                            
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
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            } else {
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
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(15)
                        .shadow(radius: 10)
                        .padding()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "hand.tap.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                            Text("Tap anywhere on the map to set a waypoint")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(15)
                        .shadow(radius: 10)
                        .padding()
                    }
                }
            }
            .navigationTitle("Set Waypoint")
            .toolbar {
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
                    }
                }
            }
        }
        .onChange(of: locationManager.location) { oldValue, newLocation in
            if let location = newLocation, selectedWaypoint == nil {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
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
                        .frame(height: 350)
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
                    VStack(spacing: 20) {
                        if let center = selectedCenter {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected Location")
                                    .font(.headline)
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
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        
                        if !offlineTileManager.downloadedRegions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Downloaded Regions")
                                    .font(.headline)
                                
                                ForEach(Array(offlineTileManager.downloadedRegions.enumerated()), id: \.element.id) { index, region in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            if editingRegionId == region.id {
                                                TextField("Region name", text: $editingRegionName, onCommit: {
                                                    offlineTileManager.updateRegionName(id: region.id, name: editingRegionName)
                                                    editingRegionId = nil
                                                })
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                            } else {
                                                Text(region.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            Text("Radius: \(region.radiusKm, specifier: "%.1f") km")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Text(region.downloadDate, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        if editingRegionId != region.id {
                                            Button(action: {
                                                editingRegionId = region.id
                                                editingRegionName = region.name
                                            }) {
                                                Image(systemName: "pencil")
                                                    .foregroundColor(.blue)
                                            }
                                            .padding(.trailing, 8)
                                        }
                                        Button(action: {
                                            offlineTileManager.deleteRegion(at: index)
                                            if editingRegionId == region.id {
                                                editingRegionId = nil
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding()
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cache Information")
                                .font(.headline)
                            
                            HStack {
                                Text("Cache Size:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(offlineTileManager.getCacheSize())
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Download Radius: \(radiusKm, specifier: "%.1f") km")
                                .font(.headline)
                            
                            Slider(value: $radiusKm, in: 1.0...20.0, step: 1.0)
                            
                            Text("Larger areas require more storage and time")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        
                        if offlineTileManager.isDownloading {
                            VStack(spacing: 10) {
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
                                        .padding()
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        } else {
                            Button(action: {
                                showDownloadAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download Maps for Selected Area")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedCenter != nil ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(selectedCenter == nil)
                            .padding(.horizontal)
                        }
                        
                        Button(action: {
                            offlineTileManager.clearCache()
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear All Cached Maps")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Information")
                                .font(.headline)
                            
                            Text("• Tap the map to select download location")
                                .font(.caption)
                            Text("• Blue circle shows selected download area")
                                .font(.caption)
                            Text("• Green circles show downloaded regions")
                                .font(.caption)
                            Text("• Tap pencil icon to rename a region")
                                .font(.caption)
                            Text("• Maps are downloaded from OpenStreetMap")
                                .font(.caption)
                            Text("• Downloaded maps work without internet")
                                .font(.caption)
                            Text("• Zoom levels 10-15 are downloaded")
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Offline Maps")
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

// MARK: - Status Card Component
struct StatusCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.headline)
            }
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}
