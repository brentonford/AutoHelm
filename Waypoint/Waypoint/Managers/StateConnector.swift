import Foundation
import Combine
import CoreLocation
import MapKit

// MARK: - State Connector
/// Bridges existing managers with the centralized state management system
@MainActor
class StateConnector: ObservableObject {
    static let shared = StateConnector()
    
    private let stateManager = AppStateManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Manager references
    private weak var bluetoothManager: BluetoothManager?
    private weak var locationManager: LocationManager?
    private weak var waypointManager: WaypointManager?
    private weak var navigationManager: NavigationManager?
    private weak var networkManager: NetworkManager?
    private weak var navigationDataManager: NavigationDataManager?
    
    private let logger = AppLogger.shared
    
    init() {
        setupStateConnections()
        logger.info("StateConnector initialized", category: .general)
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Manager Registration
    
    func register(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        connectBluetoothManager()
    }
    
    func register(locationManager: LocationManager) {
        self.locationManager = locationManager
        connectLocationManager()
    }
    
    func register(waypointManager: WaypointManager) {
        self.waypointManager = waypointManager
        connectWaypointManager()
    }
    
    func register(navigationManager: NavigationManager) {
        self.navigationManager = navigationManager
        connectNavigationManager()
    }
    
    func register(networkManager: NetworkManager) {
        self.networkManager = networkManager
        connectNetworkManager()
    }
    
    func register(navigationDataManager: NavigationDataManager) {
        self.navigationDataManager = navigationDataManager
        connectNavigationDataManager()
    }
    
    // MARK: - State Connections
    
    private func setupStateConnections() {
        // Listen to state changes and sync with managers
        stateManager.bluetoothStatePublisher
            .sink { [weak self] bluetoothState in
                self?.syncBluetoothState(bluetoothState)
            }
            .store(in: &cancellables)
        
        stateManager.waypointStatePublisher
            .map(\.waypoints)
            .removeDuplicates()
            .sink { [weak self] waypoints in
                self?.syncWaypointData(waypoints)
            }
            .store(in: &cancellables)
        
        stateManager.navigationStatePublisher
            .sink { [weak self] navigationState in
                self?.syncNavigationState(navigationState)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Bluetooth Manager Connection
    
    private func connectBluetoothManager() {
        guard let bluetoothManager = bluetoothManager else { return }
        
        // Sync existing Bluetooth manager state to central state
        stateManager.dispatch(.updateBluetoothConnection(bluetoothManager.isConnected))
        stateManager.dispatch(.updateBluetoothScanning(bluetoothManager.isScanning))
        
        if let deviceStatus = bluetoothManager.deviceStatus {
            stateManager.dispatch(.updateDeviceStatus(deviceStatus))
        }
        
        // Listen to Bluetooth manager changes
        bluetoothManager.connectionStatePublisher
            .sink { [weak self] isConnected in
                self?.stateManager.dispatch(.updateBluetoothConnection(isConnected))
            }
            .store(in: &cancellables)
        
        bluetoothManager.scanningStatePublisher
            .sink { [weak self] isScanning in
                self?.stateManager.dispatch(.updateBluetoothScanning(isScanning))
            }
            .store(in: &cancellables)
        
        bluetoothManager.deviceStatusPublisher
            .sink { [weak self] deviceStatus in
                self?.stateManager.dispatch(.updateDeviceStatus(deviceStatus))
                
                // Also update location if we have GPS data from device
                if let coordinate = deviceStatus.targetCoordinate {
                    self?.stateManager.dispatch(.setNavigationTarget(coordinate))
                }
            }
            .store(in: &cancellables)
        
        logger.info("BluetoothManager connected to state", category: .bluetooth)
    }
    
    private func syncBluetoothState(_ bluetoothState: BluetoothState) {
        // Sync state changes back to Bluetooth manager if needed
        // Most Bluetooth operations are initiated by the manager itself
        logger.debug("Syncing bluetooth state: connected=\(bluetoothState.isConnected)", category: .bluetooth)
    }
    
    // MARK: - Location Manager Connection
    
    private func connectLocationManager() {
        guard let locationManager = locationManager else { return }
        
        // Sync existing location state
        if let location = locationManager.userLocation {
            stateManager.dispatch(.updateLocation(location))
        }
        
        stateManager.dispatch(.updateLocationPermission(Int(locationManager.authorizationStatus.rawValue)))
        stateManager.dispatch(.updateLocationAccuracy(locationManager.locationAccuracy))
        
        // Listen to location updates
        locationManager.coordinatePublisher
            .sink { [weak self] coordinate in
                self?.stateManager.dispatch(.updateLocation(coordinate))
            }
            .store(in: &cancellables)
        
        locationManager.authorizationPublisher
            .sink { [weak self] status in
                self?.stateManager.dispatch(.updateLocationPermission(Int(status.rawValue)))
            }
            .store(in: &cancellables)
        
        locationManager.accuracyPublisher
            .sink { [weak self] accuracy in
                self?.stateManager.dispatch(.updateLocationAccuracy(accuracy))
            }
            .store(in: &cancellables)
        
        logger.info("LocationManager connected to state", category: .location)
    }
    
    // MARK: - Waypoint Manager Connection
    
    private func connectWaypointManager() {
        guard let waypointManager = waypointManager else { return }
        
        // Sync existing waypoints
        let existingWaypoints = waypointManager.waypoints
        for waypoint in existingWaypoints {
            stateManager.dispatch(.addWaypoint(waypoint))
        }
        
        if let selected = waypointManager.selectedWaypoint {
            stateManager.dispatch(.selectWaypoint(selected))
        }
        
        // Listen to waypoint changes
        waypointManager.waypointsPublisher
            .sink { [weak self] waypoints in
                // Sync waypoints to state (replace all)
                let currentWaypoints = self?.stateManager.state.waypoints.waypoints ?? []
                let newWaypoints = waypoints
                
                // Find added waypoints
                for waypoint in newWaypoints {
                    if !currentWaypoints.contains(where: { $0.id == waypoint.id }) {
                        self?.stateManager.dispatch(.addWaypoint(waypoint))
                    }
                }
                
                // Find removed waypoints
                for waypoint in currentWaypoints {
                    if !newWaypoints.contains(where: { $0.id == waypoint.id }) {
                        self?.stateManager.dispatch(.deleteWaypoint(waypoint.id))
                    }
                }
                
                // Find updated waypoints
                for waypoint in newWaypoints {
                    if let existing = currentWaypoints.first(where: { $0.id == waypoint.id }),
                       existing != waypoint {
                        self?.stateManager.dispatch(.updateWaypoint(waypoint))
                    }
                }
            }
            .store(in: &cancellables)
        
        logger.info("WaypointManager connected to state", category: .waypoints)
    }
    
    private func syncWaypointData(_ waypoints: [Waypoint]) {
        // Sync waypoint changes back to waypoint manager if needed
        // In practice, the waypoint manager is usually the source of truth
        logger.debug("Syncing \(waypoints.count) waypoints", category: .waypoints)
    }
    
    // MARK: - Navigation Manager Connection
    
    private func connectNavigationManager() {
        guard let navigationManager = navigationManager else { return }
        
        // Sync existing navigation state
        stateManager.dispatch(.selectTab(navigationManager.selectedTab))
        
        // Listen to navigation changes
        navigationManager.selectedTabPublisher
            .sink { [weak self] selectedTab in
                self?.stateManager.dispatch(.selectTab(selectedTab))
            }
            .store(in: &cancellables)
        
        navigationManager.navigationStatePublisher
            .sink { [weak self] navState in
                self?.stateManager.dispatch(.selectTab(navState.selectedTab))
            }
            .store(in: &cancellables)
        
        logger.info("NavigationManager connected to state", category: .navigation)
    }
    
    private func syncNavigationState(_ navigationState: NavigationState) {
        // Sync navigation state changes back to navigation manager
        if let navigationManager = navigationManager,
           navigationManager.selectedTab != navigationState.selectedTab {
            navigationManager.selectTab(navigationState.selectedTab)
        }
    }
    
    // MARK: - Network Manager Connection
    
    private func connectNetworkManager() {
        guard let networkManager = networkManager else { return }
        
        // Sync existing network state
        stateManager.dispatch(.updateNetworkConnection(networkManager.isConnectedToInternet))
        stateManager.dispatch(.updateNetworkType(networkManager.currentNetworkType.rawValue))
        stateManager.dispatch(.updateRequestQueueCount(networkManager.requestQueueCount))
        
        // Listen to network changes
        Publishers.CombineLatest4(
            networkManager.$isConnectedToInternet,
            networkManager.$currentNetworkType,
            networkManager.$requestQueueCount,
            Just(networkManager.getCacheSize()).eraseToAnyPublisher()
        )
        .sink { [weak self] isConnected, networkType, queueCount, cacheSize in
            self?.stateManager.dispatch(.batchUpdate([
                .updateNetworkConnection(isConnected),
                .updateNetworkType(String(describing: networkType)),
                .updateRequestQueueCount(queueCount),
                .updateCacheSize(cacheSize)
            ]))
        }
        .store(in: &cancellables)
        
        logger.info("NetworkManager connected to state", category: .networking)
    }
    
    // MARK: - Navigation Data Manager Connection
    
    private func connectNavigationDataManager() {
        guard let navigationDataManager = navigationDataManager else { return }
        
        // Listen to navigation data changes
        navigationDataManager.navigationDataPublisher
            .sink { [weak self] navigationData in
                self?.stateManager.dispatch(.batchUpdate([
                    .updateNavigationState(navigationData.state),
                    .updateNavigationData(distance: navigationData.distance, bearing: navigationData.bearing)
                ]))
            }
            .store(in: &cancellables)
        
        logger.info("NavigationDataManager connected to state", category: .navigation)
    }
    
    // MARK: - Public State Access
    
    var currentState: AppState {
        stateManager.state
    }
    
    func dispatch(_ action: AppAction) {
        stateManager.dispatch(action)
    }
    
    // MARK: - Convenience Methods for Common Operations
    
    func sendWaypointToDevice(_ waypoint: Waypoint) {
        guard let bluetoothManager = bluetoothManager else {
            logger.warning("Cannot send waypoint - BluetoothManager not registered", category: .bluetooth)
            return
        }
        
        bluetoothManager.sendWaypoint(latitude: waypoint.coordinate.latitude,
                                    longitude: waypoint.coordinate.longitude)
        dispatch(.setNavigationTarget(waypoint.coordinate))
        dispatch(.selectWaypoint(waypoint))
    }
    
    func createWaypoint(at coordinate: CLLocationCoordinate2D, name: String? = nil) {
        let waypointName = name ?? "Waypoint \(currentState.waypoints.waypoints.count + 1)"
        let waypoint = Waypoint(coordinate: coordinate, name: waypointName)
        
        waypointManager?.saveWaypoint(waypoint)
        dispatch(.addWaypoint(waypoint))
    }
    
    func updateMapType(_ mapType: MKMapType) {
        dispatch(.setMapType(Int(mapType.rawValue)))
        
        // Also update any UI managers that need to know about map type changes
        logger.debug("Map type updated to: \(mapType)", category: .ui)
    }
}

// MARK: - State Connector Extensions
extension StateConnector {
    /// Get filtered waypoints based on current search and sort criteria
    func getFilteredWaypoints() -> [Waypoint] {
        let waypointState = currentState.waypoints
        var filteredWaypoints = waypointState.waypoints
        
        // Apply search filter
        if !waypointState.searchText.isEmpty {
            filteredWaypoints = filteredWaypoints.filter { waypoint in
                waypoint.name.localizedCaseInsensitiveContains(waypointState.searchText) ||
                waypoint.comments.localizedCaseInsensitiveContains(waypointState.searchText)
            }
        }
        
        // Apply sort order
        switch waypointState.sortOrder {
        case .name:
            filteredWaypoints.sort { $0.name < $1.name }
        case .dateCreated:
            filteredWaypoints.sort { $0.createdDate > $1.createdDate }
        case .dateModified:
            filteredWaypoints.sort { $0.lastUpdatedDate > $1.lastUpdatedDate }
        case .distance:
            if let currentLocation = currentState.location.currentLocation {
                let currentCLLocation = CLLocation(latitude: currentLocation.latitude,
                                                 longitude: currentLocation.longitude)
                filteredWaypoints.sort { waypoint1, waypoint2 in
                    let location1 = CLLocation(latitude: waypoint1.coordinate.latitude,
                                             longitude: waypoint1.coordinate.longitude)
                    let location2 = CLLocation(latitude: waypoint2.coordinate.latitude,
                                             longitude: waypoint2.coordinate.longitude)
                    return currentCLLocation.distance(from: location1) < currentCLLocation.distance(from: location2)
                }
            }
        }
        
        return filteredWaypoints
    }
    
    /// Get current navigation summary
    func getNavigationSummary() -> NavigationSummary {
        let state = currentState
        return NavigationSummary(
            isNavigating: state.navigation.isNavigating,
            currentTarget: state.navigation.currentTarget,
            distanceToTarget: state.navigation.distanceToTarget,
            bearingToTarget: state.navigation.bearingToTarget,
            navigationState: state.navigation.navigationState,
            isBluetoothConnected: state.bluetooth.isConnected,
            hasGpsFix: state.bluetooth.deviceStatus?.hasGpsFix ?? false
        )
    }
}

// MARK: - Supporting Types
struct NavigationSummary {
    let isNavigating: Bool
    let currentTarget: CLLocationCoordinate2D?
    let distanceToTarget: Double
    let bearingToTarget: Double
    let navigationState: AppNavigationState
    let isBluetoothConnected: Bool
    let hasGpsFix: Bool
    
    var canNavigate: Bool {
        return isBluetoothConnected && hasGpsFix && currentTarget != nil
    }
    
    var statusDescription: String {
        if !isBluetoothConnected {
            return "Bluetooth disconnected"
        } else if !hasGpsFix {
            return "No GPS fix"
        } else if currentTarget == nil {
            return "No target selected"
        } else {
            return navigationState.description
        }
    }
}

// Make NetworkManager.NetworkType have a raw value
extension NetworkManager.NetworkType: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .bluetooth: return "bluetooth"
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case "none": self = .none
        case "wifi": self = .wifi
        case "cellular": self = .cellular
        case "bluetooth": self = .bluetooth
        default: return nil
        }
    }
}