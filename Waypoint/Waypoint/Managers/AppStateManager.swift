import Foundation
import Combine
import CoreLocation

// MARK: - App State Structure
struct AppState: Equatable, Codable {
    var navigation: NavigationState
    var location: LocationState
    var waypoints: WaypointState
    var bluetooth: BluetoothState
    var ui: UIState
    var settings: SettingsState
    var network: NetworkState
    
    static let initial = AppState(
        navigation: NavigationState(),
        location: LocationState(),
        waypoints: WaypointState(),
        bluetooth: BluetoothState(),
        ui: UIState(),
        settings: SettingsState(),
        network: NetworkState()
    )
}

// MARK: - State Components
struct NavigationState: Equatable, Codable {
    var selectedTab: TabRoute = .map
    var mapPathCount: Int = 0
    var helmPathCount: Int = 0
    var currentTarget: CLLocationCoordinate2D?
    var isNavigating: Bool = false
    var navigationState: AppNavigationState = .idle
    var distanceToTarget: Double = 0
    var bearingToTarget: Double = 0
}

struct LocationState: Equatable, Codable {
    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: Int = 0 // CLAuthorizationStatus raw value
    var isLocationServicesEnabled: Bool = false
    var accuracy: Double = 0.0
    var lastUpdated: Date = Date()
}

struct WaypointState: Equatable, Codable {
    var waypoints: [Waypoint] = []
    var selectedWaypoint: Waypoint?
    var isLoading: Bool = false
    var searchText: String = ""
    var sortOrder: WaypointSortOrder = .name
    
    enum WaypointSortOrder: String, Codable, CaseIterable {
        case name
        case distance
        case dateCreated
        case dateModified
    }
}

struct BluetoothState: Equatable, Codable {
    var isConnected: Bool = false
    var isScanning: Bool = false
    var deviceStatus: DeviceStatus?
    var lastConnectionTime: Date?
    var connectionAttempts: Int = 0
}

struct UIState: Equatable, Codable {
    var mapType: Int = 0 // MKMapType raw value
    var showingWaypointAlert: Bool = false
    var showingSettings: Bool = false
    var isLoadingSatellite: Bool = false
    var selectedMapRegion: MapRegion?
    
    struct MapRegion: Equatable, Codable {
        let centerLatitude: Double
        let centerLongitude: Double
        let spanLatitude: Double
        let spanLongitude: Double
    }
}

struct SettingsState: Equatable, Codable {
    var logLevel: String = "info"
    var remoteLoggingEnabled: Bool = false
    var clusteringEnabled: Bool = true
    var clusterRadius: Double = 100.0
    var autoSaveInterval: Double = 30.0
}

struct NetworkState: Equatable, Codable {
    var isConnectedToInternet: Bool = false
    var networkType: String = "none"
    var requestQueueCount: Int = 0
    var cacheSize: Int64 = 0
    var lastSyncTime: Date?
}

// MARK: - Actions
enum AppAction {
    // Navigation Actions
    case selectTab(TabRoute)
    case navigateToWaypoint(Waypoint)
    case popNavigation
    case setNavigationTarget(CLLocationCoordinate2D)
    case updateNavigationState(AppNavigationState)
    case updateNavigationData(distance: Double, bearing: Double)
    
    // Location Actions
    case updateLocation(CLLocationCoordinate2D)
    case updateLocationPermission(Int)
    case updateLocationAccuracy(Double)
    
    // Waypoint Actions
    case addWaypoint(Waypoint)
    case updateWaypoint(Waypoint)
    case deleteWaypoint(UUID)
    case selectWaypoint(Waypoint?)
    case setWaypointsLoading(Bool)
    case updateSearchText(String)
    case setSortOrder(WaypointState.WaypointSortOrder)
    
    // Bluetooth Actions
    case updateBluetoothConnection(Bool)
    case updateBluetoothScanning(Bool)
    case updateDeviceStatus(DeviceStatus)
    case incrementConnectionAttempts
    case resetConnectionAttempts
    
    // UI Actions
    case setMapType(Int)
    case showWaypointAlert(Bool)
    case showSettings(Bool)
    case setLoadingSatellite(Bool)
    case updateMapRegion(UIState.MapRegion)
    
    // Settings Actions
    case updateLogLevel(String)
    case toggleRemoteLogging
    case updateClusteringEnabled(Bool)
    case updateClusterRadius(Double)
    case updateAutoSaveInterval(Double)
    
    // Network Actions
    case updateNetworkConnection(Bool)
    case updateNetworkType(String)
    case updateRequestQueueCount(Int)
    case updateCacheSize(Int64)
    case updateSyncTime(Date)
    
    // Batch Actions
    case batchUpdate([AppAction])
    case resetToInitial
}

// MARK: - App State Manager
@MainActor
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published private(set) var state: AppState = AppState.initial
    
    private let stateSubject = PassthroughSubject<AppState, Never>()
    private let actionSubject = PassthroughSubject<AppAction, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let logger = AppLogger.shared
    
    // Middleware
    private var middleware: [StateMiddleware] = []
    
    // State persistence
    private let persistenceKey = "AppState"
    private let persistenceDebounceTime: DispatchTimeInterval = .milliseconds(1000)
    
    // Publishers
    var statePublisher: AnyPublisher<AppState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    var actionPublisher: AnyPublisher<AppAction, Never> {
        actionSubject.eraseToAnyPublisher()
    }
    
    // Specific state publishers
    var navigationStatePublisher: AnyPublisher<NavigationState, Never> {
        stateSubject.map(\.navigation).removeDuplicates().eraseToAnyPublisher()
    }
    
    var waypointStatePublisher: AnyPublisher<WaypointState, Never> {
        stateSubject.map(\.waypoints).removeDuplicates().eraseToAnyPublisher()
    }
    
    var bluetoothStatePublisher: AnyPublisher<BluetoothState, Never> {
        stateSubject.map(\.bluetooth).removeDuplicates().eraseToAnyPublisher()
    }
    
    var locationStatePublisher: AnyPublisher<LocationState, Never> {
        stateSubject.map(\.location).removeDuplicates().eraseToAnyPublisher()
    }
    
    init() {
        setupStateManagement()
        setupMiddleware()
        loadPersistedState()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupStateManagement() {
        // Action processing pipeline
        actionSubject
            .sink { [weak self] action in
                self?.processAction(action)
            }
            .store(in: &cancellables)
        
        // State change notifications
        $state
            .sink { [weak self] newState in
                self?.stateSubject.send(newState)
            }
            .store(in: &cancellables)
        
        // Debounced state persistence
        stateSubject
            .debounce(for: .milliseconds(1000), scheduler: RunLoop.main)
            .sink { [weak self] state in
                self?.persistState(state)
            }
            .store(in: &cancellables)
    }
    
    private func setupMiddleware() {
        // Add logging middleware
        addMiddleware(LoggingMiddleware(logger: logger))
        
        // Add performance monitoring middleware
        addMiddleware(PerformanceMiddleware(logger: logger))
        
        // Add validation middleware
        addMiddleware(ValidationMiddleware())
    }
    
    // MARK: - Public Interface
    
    func dispatch(_ action: AppAction) {
        logger.debug("Dispatching action: \(action)", category: .general)
        actionSubject.send(action)
    }
    
    func addMiddleware(_ middleware: StateMiddleware) {
        self.middleware.append(middleware)
    }
    
    private func processAction(_ action: AppAction) {
        let oldState = state
        
        // Apply middleware (pre-processing)
        for middleware in middleware {
            middleware.beforeAction(action: action, state: oldState)
        }
        
        // Apply reducer
        state = reduce(state: oldState, action: action)
        
        // Apply middleware (post-processing)
        for middleware in middleware {
            middleware.afterAction(action: action, oldState: oldState, newState: state)
        }
    }
    
    // MARK: - Reducer
    
    private func reduce(state: AppState, action: AppAction) -> AppState {
        var newState = state
        
        switch action {
        // Navigation Actions
        case .selectTab(let tab):
            newState.navigation.selectedTab = tab
            
        case .navigateToWaypoint(let waypoint):
            newState.navigation.currentTarget = waypoint.coordinate
            newState.waypoints.selectedWaypoint = waypoint
            
        case .popNavigation:
            if newState.navigation.selectedTab == .map {
                newState.navigation.mapPathCount = max(0, newState.navigation.mapPathCount - 1)
            } else {
                newState.navigation.helmPathCount = max(0, newState.navigation.helmPathCount - 1)
            }
            
        case .setNavigationTarget(let coordinate):
            newState.navigation.currentTarget = coordinate
            newState.navigation.isNavigating = true
            
        case .updateNavigationState(let navState):
            newState.navigation.navigationState = navState
            newState.navigation.isNavigating = navState == .navigating
            
        case .updateNavigationData(let distance, let bearing):
            newState.navigation.distanceToTarget = distance
            newState.navigation.bearingToTarget = bearing
            
        // Location Actions
        case .updateLocation(let coordinate):
            newState.location.currentLocation = coordinate
            newState.location.lastUpdated = Date()
            
        case .updateLocationPermission(let status):
            newState.location.authorizationStatus = status
            
        case .updateLocationAccuracy(let accuracy):
            newState.location.accuracy = accuracy
            
        // Waypoint Actions
        case .addWaypoint(let waypoint):
            newState.waypoints.waypoints.append(waypoint)
            
        case .updateWaypoint(let waypoint):
            if let index = newState.waypoints.waypoints.firstIndex(where: { $0.id == waypoint.id }) {
                newState.waypoints.waypoints[index] = waypoint
            }
            
        case .deleteWaypoint(let id):
            newState.waypoints.waypoints.removeAll { $0.id == id }
            if newState.waypoints.selectedWaypoint?.id == id {
                newState.waypoints.selectedWaypoint = nil
            }
            
        case .selectWaypoint(let waypoint):
            newState.waypoints.selectedWaypoint = waypoint
            
        case .setWaypointsLoading(let loading):
            newState.waypoints.isLoading = loading
            
        case .updateSearchText(let text):
            newState.waypoints.searchText = text
            
        case .setSortOrder(let order):
            newState.waypoints.sortOrder = order
            
        // Bluetooth Actions
        case .updateBluetoothConnection(let connected):
            newState.bluetooth.isConnected = connected
            if connected {
                newState.bluetooth.lastConnectionTime = Date()
                newState.bluetooth.connectionAttempts = 0
            }
            
        case .updateBluetoothScanning(let scanning):
            newState.bluetooth.isScanning = scanning
            
        case .updateDeviceStatus(let status):
            newState.bluetooth.deviceStatus = status
            
        case .incrementConnectionAttempts:
            newState.bluetooth.connectionAttempts += 1
            
        case .resetConnectionAttempts:
            newState.bluetooth.connectionAttempts = 0
            
        // UI Actions
        case .setMapType(let type):
            newState.ui.mapType = type
            
        case .showWaypointAlert(let show):
            newState.ui.showingWaypointAlert = show
            
        case .showSettings(let show):
            newState.ui.showingSettings = show
            
        case .setLoadingSatellite(let loading):
            newState.ui.isLoadingSatellite = loading
            
        case .updateMapRegion(let region):
            newState.ui.selectedMapRegion = region
            
        // Settings Actions
        case .updateLogLevel(let level):
            newState.settings.logLevel = level
            
        case .toggleRemoteLogging:
            newState.settings.remoteLoggingEnabled.toggle()
            
        case .updateClusteringEnabled(let enabled):
            newState.settings.clusteringEnabled = enabled
            
        case .updateClusterRadius(let radius):
            newState.settings.clusterRadius = radius
            
        case .updateAutoSaveInterval(let interval):
            newState.settings.autoSaveInterval = interval
            
        // Network Actions
        case .updateNetworkConnection(let connected):
            newState.network.isConnectedToInternet = connected
            
        case .updateNetworkType(let type):
            newState.network.networkType = type
            
        case .updateRequestQueueCount(let count):
            newState.network.requestQueueCount = count
            
        case .updateCacheSize(let size):
            newState.network.cacheSize = size
            
        case .updateSyncTime(let date):
            newState.network.lastSyncTime = date
            
        // Batch Actions
        case .batchUpdate(let actions):
            for action in actions {
                newState = reduce(state: newState, action: action)
            }
            
        case .resetToInitial:
            newState = AppState.initial
        }
        
        return newState
    }
    
    // MARK: - State Persistence
    
    private func loadPersistedState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let persistedState = try? JSONDecoder().decode(AppState.self, from: data) else {
            logger.info("No persisted state found, using initial state", category: .general)
            return
        }
        
        state = persistedState
        logger.info("Loaded persisted app state", category: .general)
    }
    
    private func persistState(_ state: AppState) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: persistenceKey)
            logger.debug("App state persisted", category: .general)
        } catch {
            logger.error("Failed to persist app state", error: error, category: .general)
        }
    }
    
    // MARK: - Convenience Methods
    
    var currentWaypoints: [Waypoint] {
        state.waypoints.waypoints
    }
    
    var isNavigating: Bool {
        state.navigation.isNavigating
    }
    
    var currentLocation: CLLocationCoordinate2D? {
        state.location.currentLocation
    }
    
    var isBluetoothConnected: Bool {
        state.bluetooth.isConnected
    }
}

// MARK: - Middleware Protocol
@preconcurrency protocol StateMiddleware {
    func beforeAction(action: AppAction, state: AppState)
    func afterAction(action: AppAction, oldState: AppState, newState: AppState)
}

// MARK: - Middleware Implementations
class LoggingMiddleware: @preconcurrency StateMiddleware {
    private let logger: AppLogger
    
    init(logger: AppLogger) {
        self.logger = logger
    }
    
    @MainActor func beforeAction(action: AppAction, state: AppState) {
        logger.debug("Action dispatched: \(action)", category: .general)
    }
    
    @MainActor func afterAction(action: AppAction, oldState: AppState, newState: AppState) {
        if oldState != newState {
            logger.debug("State changed after action: \(action)", category: .general)
        }
    }
}

class PerformanceMiddleware: @preconcurrency StateMiddleware {
    private let logger: AppLogger
    private var actionStartTimes: [String: Date] = [:]
    
    init(logger: AppLogger) {
        self.logger = logger
    }
    
    @MainActor func beforeAction(action: AppAction, state: AppState) {
        let actionKey = String(describing: action)
        actionStartTimes[actionKey] = Date()
        logger.startPerformanceMeasurement("action_\(actionKey)", category: .performance)
    }
    
    @MainActor func afterAction(action: AppAction, oldState: AppState, newState: AppState) {
        let actionKey = String(describing: action)
        logger.endPerformanceMeasurement("action_\(actionKey)", category: .performance)
        actionStartTimes.removeValue(forKey: actionKey)
    }
}

class ValidationMiddleware: StateMiddleware {
    func beforeAction(action: AppAction, state: AppState) {
        // Validate action preconditions
        switch action {
        case .setNavigationTarget(let coordinate):
            guard coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
                  coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
                print("Invalid coordinates in setNavigationTarget: \(coordinate)")
                return
            }
        default:
            break
        }
    }
    
    func afterAction(action: AppAction, oldState: AppState, newState: AppState) {
        // Validate state consistency
        if newState.waypoints.selectedWaypoint != nil &&
           !newState.waypoints.waypoints.contains(where: { $0.id == newState.waypoints.selectedWaypoint?.id }) {
            print("Inconsistent state: selected waypoint not in waypoints array")
        }
    }
}