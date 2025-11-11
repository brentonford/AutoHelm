import Foundation
import Network
import Combine
import CoreLocation

// MARK: - Network Request Types
enum NetworkRequestType {
    case openStreetMap(TileRequest)
    case weather(WeatherRequest)
    case waypointSync(WaypointSyncRequest)
}

struct TileRequest {
    let x: Int
    let y: Int
    let z: Int
}

struct WeatherRequest {
    let coordinate: CLLocationCoordinate2D
    let apiKey: String
}

struct WaypointSyncRequest {
    let waypoints: [Waypoint]
    let deviceId: String
}

// MARK: - Network Response Types
enum NetworkResponse {
    case tileData(Data)
    case weatherData(WeatherData)
    case syncResponse(SyncResponse)
    case error(NetworkError)
}

struct WeatherData: Codable {
    let temperature: Double
    let conditions: String
    let windSpeed: Double
    let visibility: Double
}

struct SyncResponse: Codable {
    let syncedCount: Int
    let conflicts: [WaypointConflict]
    let timestamp: Date
}

struct WaypointConflict: Codable {
    let localWaypoint: Waypoint
    let remoteWaypoint: Waypoint
    let conflictType: ConflictType
    
    enum ConflictType: String, Codable {
        case nameConflict
        case locationConflict
        case timestampConflict
    }
}

// MARK: - Network Error Types
enum NetworkError: Error, LocalizedError {
    case noConnection
    case timeout
    case invalidResponse
    case serverError(Int)
    case rateLimited
    case apiKeyInvalid
    case bluetoothUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No network connection available"
        case .timeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .rateLimited:
            return "API rate limit exceeded"
        case .apiKeyInvalid:
            return "Invalid API key"
        case .bluetoothUnavailable:
            return "Bluetooth connection unavailable"
        }
    }
}

// MARK: - Network Configuration
struct NetworkConfiguration {
    let baseURL: String
    let apiKey: String
    let timeout: TimeInterval
    let retryCount: Int
    let enableCaching: Bool
    
    static let openStreetMap = NetworkConfiguration(
        baseURL: "https://tile.openstreetmap.org",
        apiKey: "",
        timeout: 30.0,
        retryCount: 3,
        enableCaching: true
    )
    
    static let weatherAPI = NetworkConfiguration(
        baseURL: "https://api.openweathermap.org/data/2.5",
        apiKey: "", // Set via configuration
        timeout: 15.0,
        retryCount: 2,
        enableCaching: true
    )
}

// MARK: - Unified Network Manager
@MainActor
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var isConnectedToInternet: Bool = false
    @Published var currentNetworkType: NetworkType = .none
    @Published var requestQueueCount: Int = 0
    
    private let bluetoothManager: BluetoothManager
    internal let urlSession: URLSession
    private let networkMonitor: NWPathMonitor
    private let requestQueue: OperationQueue
    private var cancellables = Set<AnyCancellable>()
    internal let logger = AppLogger.shared
    
    // Request caching
    private let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
    
    // Publishers for different network operations
    private let networkRequestSubject = PassthroughSubject<NetworkRequestType, Never>()
    private let networkResponseSubject = PassthroughSubject<NetworkResponse, Never>()
    
    enum NetworkType {
        case none
        case wifi
        case cellular
        case bluetooth
    }
    
    // Public publishers
    var networkRequestPublisher: AnyPublisher<NetworkRequestType, Never> {
        networkRequestSubject.eraseToAnyPublisher()
    }
    
    var networkResponsePublisher: AnyPublisher<NetworkResponse, Never> {
        networkResponseSubject.eraseToAnyPublisher()
    }
    
    init(bluetoothManager: BluetoothManager? = nil) {
        self.bluetoothManager = bluetoothManager ?? BluetoothManager()
        
        // Configure URL session with caching
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)
        
        // Configure request queue
        self.requestQueue = OperationQueue()
        self.requestQueue.maxConcurrentOperationCount = 3
        self.requestQueue.qualityOfService = .userInitiated
        
        // Network monitoring
        self.networkMonitor = NWPathMonitor()
        
        setupNetworkMonitoring()
        setupRequestPipeline()
    }
    
    deinit {
        networkMonitor.cancel()
        cancellables.removeAll()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnectedToInternet = path.status == .satisfied
                self?.currentNetworkType = self?.getNetworkType(from: path) ?? .none
                
                if path.status == .satisfied {
                    self?.logger.info("Network connection available: \(self?.currentNetworkType ?? .none)", category: .networking)
                } else {
                    self?.logger.warning("Network connection lost", category: .networking)
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    private func getNetworkType(from path: NWPath) -> NetworkType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if bluetoothManager.isConnected {
            return .bluetooth
        }
        return .none
    }
    
    private func setupRequestPipeline() {
        // Monitor request queue changes
        requestQueue.publisher(for: \.operationCount)
            .receive(on: DispatchQueue.main)
            .assign(to: &$requestQueueCount)
        
        // Handle network request routing
        networkRequestSubject
            .sink { [weak self] requestType in
                self?.routeRequest(requestType)
            }
            .store(in: &cancellables)
        
        // Monitor Bluetooth connection changes
        bluetoothManager.connectionStatePublisher
            .sink { [weak self] isConnected in
                if !isConnected && self?.currentNetworkType == .bluetooth {
                    self?.currentNetworkType = self?.isConnectedToInternet == true ? .wifi : .none
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Interface
    
    func performRequest(_ requestType: NetworkRequestType) -> AnyPublisher<NetworkResponse, NetworkError> {
        logger.startPerformanceMeasurement("network_request", category: .networking)
        
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.noConnection))
                return
            }
            
            let operation = NetworkOperation(
                requestType: requestType,
                networkManager: self,
                completion: { result in
                    self.logger.endPerformanceMeasurement("network_request", category: .networking)
                    promise(result)
                }
            )
            
            self.requestQueue.addOperation(operation)
        }
        .handleEvents(
            receiveSubscription: { [weak self] _ in
                self?.networkRequestSubject.send(requestType)
            },
            receiveOutput: { [weak self] response in
                self?.networkResponseSubject.send(response)
            }
        )
        .eraseToAnyPublisher()
    }
    
    private func routeRequest(_ requestType: NetworkRequestType) {
        switch requestType {
        case .openStreetMap:
            logger.debug("Routing OpenStreetMap request", category: .networking)
        case .weather:
            logger.debug("Routing weather API request", category: .networking)
        case .waypointSync:
            logger.debug("Routing waypoint sync request", category: .networking)
        }
    }
    
    // MARK: - Specific Network Operations
    
    func downloadMapTile(x: Int, y: Int, z: Int) -> AnyPublisher<Data, NetworkError> {
        let request = NetworkRequestType.openStreetMap(TileRequest(x: x, y: y, z: z))
        
        return performRequest(request)
            .compactMap { response in
                if case .tileData(let data) = response {
                    return data
                }
                return nil
            }
            .mapError { $0 }
            .eraseToAnyPublisher()
    }
    
    func fetchWeather(for coordinate: CLLocationCoordinate2D, apiKey: String) -> AnyPublisher<WeatherData, NetworkError> {
        let request = NetworkRequestType.weather(WeatherRequest(coordinate: coordinate, apiKey: apiKey))
        
        return performRequest(request)
            .compactMap { response in
                if case .weatherData(let weather) = response {
                    return weather
                }
                return nil
            }
            .mapError { $0 }
            .eraseToAnyPublisher()
    }
    
    func syncWaypoints(_ waypoints: [Waypoint], deviceId: String) -> AnyPublisher<SyncResponse, NetworkError> {
        let request = NetworkRequestType.waypointSync(WaypointSyncRequest(waypoints: waypoints, deviceId: deviceId))
        
        return performRequest(request)
            .compactMap { response in
                if case .syncResponse(let sync) = response {
                    return sync
                }
                return nil
            }
            .mapError { $0 }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Bluetooth Integration
    
    func sendWaypointViaBluetooth(latitude: Double, longitude: Double) -> AnyPublisher<Void, NetworkError> {
        guard bluetoothManager.isConnected else {
            return Fail(error: NetworkError.bluetoothUnavailable)
                .eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            self?.bluetoothManager.sendWaypoint(latitude: latitude, longitude: longitude)
            promise(.success(()))
        }
        .eraseToAnyPublisher()
    }
    
    func enableNavigationViaBluetooth() -> AnyPublisher<Void, NetworkError> {
        guard bluetoothManager.isConnected else {
            return Fail(error: NetworkError.bluetoothUnavailable)
                .eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            self?.bluetoothManager.enableNavigation()
            promise(.success(()))
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Cache Management
    
    func clearNetworkCache() {
        cache.removeAllCachedResponses()
        logger.info("Network cache cleared", category: .networking)
    }
    
    func getCacheSize() -> Int64 {
        return Int64(cache.currentMemoryUsage + cache.currentDiskUsage)
    }
}

// MARK: - Network Operation
private class NetworkOperation: Operation, @unchecked Sendable {
    private let requestType: NetworkRequestType
    private weak var networkManager: NetworkManager?
    private let completion: (Result<NetworkResponse, NetworkError>) -> Void
    
    init(requestType: NetworkRequestType, networkManager: NetworkManager, completion: @escaping (Result<NetworkResponse, NetworkError>) -> Void) {
        self.requestType = requestType
        self.networkManager = networkManager
        self.completion = completion
        super.init()
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        switch requestType {
        case .openStreetMap(let tile):
            downloadTile(tile)
        case .weather(let weather):
            fetchWeatherData(weather)
        case .waypointSync(let sync):
            performWaypointSync(sync)
        }
    }
    
    private func downloadTile(_ tile: TileRequest) {
        guard let networkManager = networkManager else {
            completion(.failure(.noConnection))
            return
        }
        
        let urlString = "https://tile.openstreetmap.org/\(tile.z)/\(tile.x)/\(tile.y).png"
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        networkManager.urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, !self.isCancelled else { return }
            
            if let error = error {
                Task { @MainActor in
                    networkManager.logger.error("Tile download failed", error: error, category: .networking)
                }
                self.completion(.failure(.timeout))
                return
            }
            
            guard let data = data else {
                self.completion(.failure(.invalidResponse))
                return
            }
            
            self.completion(.success(.tileData(data)))
        }.resume()
    }
    
    private func fetchWeatherData(_ weather: WeatherRequest) {
        // Implementation for weather API
        completion(.success(.weatherData(WeatherData(temperature: 20.0, conditions: "Clear", windSpeed: 5.0, visibility: 10.0))))
    }
    
    private func performWaypointSync(_ sync: WaypointSyncRequest) {
        // Implementation for waypoint synchronization
        completion(.success(.syncResponse(SyncResponse(syncedCount: sync.waypoints.count, conflicts: [], timestamp: Date()))))
    }
}

// MARK: - Network Manager Extensions
extension NetworkManager {
    /// Batch download multiple map tiles
    func downloadTiles(_ tiles: [TileURL]) -> AnyPublisher<[Data], NetworkError> {
        let publishers = tiles.map { tile in
            downloadMapTile(x: tile.x, y: tile.y, z: tile.z)
        }
        
        return Publishers.MergeMany(publishers)
            .collect()
            .eraseToAnyPublisher()
    }
    
    /// Check if specific API is reachable
    func checkAPIReachability(for configuration: NetworkConfiguration) -> AnyPublisher<Bool, Never> {
        guard let url = URL(string: configuration.baseURL) else {
            return Just(false).eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5.0
            
            self?.urlSession.dataTask(with: request) { _, response, _ in
                if let httpResponse = response as? HTTPURLResponse {
                    promise(.success(200...299 ~= httpResponse.statusCode))
                } else {
                    promise(.success(false))
                }
            }.resume()
        }
        .eraseToAnyPublisher()
    }
}