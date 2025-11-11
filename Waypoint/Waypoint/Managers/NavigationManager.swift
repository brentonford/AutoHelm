import SwiftUI
import Foundation
import Combine

// MARK: - Navigation Route Definitions
enum AppRoute: Hashable {
    case map
    case helm
    case waypointDetail(Waypoint)
    case waypointList
    case settings
    case bluetoothSettings
    case about
    
    var displayName: String {
        switch self {
        case .map: return "Map"
        case .helm: return "Helm Control"
        case .waypointDetail(_): return "Waypoint Details"
        case .waypointList: return "Waypoints"
        case .settings: return "Settings"
        case .bluetoothSettings: return "Bluetooth Settings"
        case .about: return "About"
        }
    }
}

// MARK: - Tab Route Definitions
enum TabRoute: String, CaseIterable {
    case map = "map"
    case helm = "helm"
    
    var systemImage: String {
        switch self {
        case .map: return "map"
        case .helm: return "helm"
        }
    }
    
    var displayName: String {
        switch self {
        case .map: return "Map"
        case .helm: return "Helm"
        }
    }
}

// MARK: - Navigation Manager
@MainActor
class NavigationManager: ObservableObject {
    @Published var selectedTab: TabRoute = .map
    @Published var mapNavigationPath = NavigationPath()
    @Published var helmNavigationPath = NavigationPath()
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = AppLogger.shared
    
    // Navigation state persistence
    private let navigationStateKey = "NavigationState"
    private let selectedTabKey = "SelectedTab"
    
    // Publishers for reactive navigation
    var selectedTabPublisher: AnyPublisher<TabRoute, Never> {
        $selectedTab.eraseToAnyPublisher()
    }
    
    var navigationStatePublisher: AnyPublisher<NavigationManagerState, Never> {
        Publishers.CombineLatest3(
            $selectedTab,
            $mapNavigationPath,
            $helmNavigationPath
        )
        .map { tab, mapPath, helmPath in
            NavigationManagerState(
                selectedTab: tab,
                mapPathCount: mapPath.count,
                helmPathCount: helmPath.count
            )
        }
        .eraseToAnyPublisher()
    }
    
    init() {
        setupNavigationStateManagement()
        restoreNavigationState()
        logger.info("NavigationManager initialized")
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Tab Navigation
    func selectTab(_ tab: TabRoute) {
        guard selectedTab != tab else { return }
        
        logger.info("Navigating to tab: \(tab.displayName)")
        selectedTab = tab
        persistNavigationState()
    }
    
    // MARK: - Programmatic Navigation
    func navigateToWaypointDetail(_ waypoint: Waypoint) {
        logger.info("Navigating to waypoint detail: \(waypoint.name)")
        
        switch selectedTab {
        case .map:
            mapNavigationPath.append(AppRoute.waypointDetail(waypoint))
        case .helm:
            helmNavigationPath.append(AppRoute.waypointDetail(waypoint))
        }
        persistNavigationState()
    }
    
    func navigateToWaypointList() {
        logger.info("Navigating to waypoint list")
        
        switch selectedTab {
        case .map:
            mapNavigationPath.append(AppRoute.waypointList)
        case .helm:
            helmNavigationPath.append(AppRoute.waypointList)
        }
        persistNavigationState()
    }
    
    func navigateToSettings() {
        logger.info("Navigating to settings")
        
        switch selectedTab {
        case .map:
            mapNavigationPath.append(AppRoute.settings)
        case .helm:
            helmNavigationPath.append(AppRoute.settings)
        }
        persistNavigationState()
    }
    
    func navigateToBluetoothSettings() {
        logger.info("Navigating to bluetooth settings")
        
        switch selectedTab {
        case .map:
            mapNavigationPath.append(AppRoute.bluetoothSettings)
        case .helm:
            helmNavigationPath.append(AppRoute.bluetoothSettings)
        }
        persistNavigationState()
    }
    
    // MARK: - Navigation Control
    func popToRoot() {
        logger.info("Popping to root for tab: \(selectedTab.displayName)")
        
        switch selectedTab {
        case .map:
            mapNavigationPath = NavigationPath()
        case .helm:
            helmNavigationPath = NavigationPath()
        }
        persistNavigationState()
    }
    
    func popLast() {
        logger.info("Popping last view for tab: \(selectedTab.displayName)")
        
        switch selectedTab {
        case .map:
            if !mapNavigationPath.isEmpty {
                mapNavigationPath.removeLast()
            }
        case .helm:
            if !helmNavigationPath.isEmpty {
                helmNavigationPath.removeLast()
            }
        }
        persistNavigationState()
    }
    
    func canGoBack() -> Bool {
        switch selectedTab {
        case .map:
            return !mapNavigationPath.isEmpty
        case .helm:
            return !helmNavigationPath.isEmpty
        }
    }
    
    // MARK: - Deep Linking Support
    func handleDeepLink(_ url: URL) -> Bool {
        logger.info("Handling deep link: \(url.absoluteString)")
        
        guard url.scheme == "waypoint" else {
            logger.warning("Unsupported URL scheme: \(url.scheme ?? "none")")
            return false
        }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        switch url.host {
        case "map":
            selectedTab = .map
            handleMapDeepLink(components)
            return true
            
        case "helm":
            selectedTab = .helm
            handleHelmDeepLink(components)
            return true
            
        case "waypoint":
            if let waypointId = components?.queryItems?.first(where: { $0.name == "id" })?.value,
               let uuid = UUID(uuidString: waypointId) {
                handleWaypointDeepLink(uuid)
                return true
            }
            return false
            
        default:
            logger.warning("Unsupported deep link host: \(url.host ?? "none")")
            return false
        }
    }
    
    private func handleMapDeepLink(_ components: URLComponents?) {
        guard let path = components?.path else { return }
        
        switch path {
        case "/waypoints":
            navigateToWaypointList()
        case "/settings":
            navigateToSettings()
        default:
            logger.info("No specific action for map deep link path: \(path)")
        }
    }
    
    private func handleHelmDeepLink(_ components: URLComponents?) {
        guard let path = components?.path else { return }
        
        switch path {
        case "/bluetooth":
            navigateToBluetoothSettings()
        case "/settings":
            navigateToSettings()
        default:
            logger.info("No specific action for helm deep link path: \(path)")
        }
    }
    
    private func handleWaypointDeepLink(_ waypointId: UUID) {
        // This would need to be coordinated with WaypointManager
        // For now, just navigate to waypoint list
        navigateToWaypointList()
        logger.info("Deep link to waypoint: \(waypointId)")
    }
    
    // MARK: - State Persistence
    private func setupNavigationStateManagement() {
        // Auto-save navigation state changes
        navigationStatePublisher
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistNavigationState()
            }
            .store(in: &cancellables)
        
        // Tab change logging
        selectedTabPublisher
            .sink { [weak self] tab in
                self?.logger.debug("Tab changed to: \(tab.displayName)")
            }
            .store(in: &cancellables)
    }
    
    private func persistNavigationState() {
        UserDefaults.standard.set(selectedTab.rawValue, forKey: selectedTabKey)
        
        let state = NavigationStateData(
            selectedTab: selectedTab.rawValue,
            mapPathCount: mapNavigationPath.count,
            helmPathCount: helmNavigationPath.count
        )
        
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: navigationStateKey)
        }
        
        logger.debug("Navigation state persisted")
    }
    
    private func restoreNavigationState() {
        // Restore selected tab
        if let savedTab = UserDefaults.standard.object(forKey: selectedTabKey) as? String,
           let tab = TabRoute(rawValue: savedTab) {
            selectedTab = tab
        }
        
        // Note: NavigationPath doesn't support full restoration of complex routes
        // This is a limitation of SwiftUI's NavigationPath - we can only restore counts
        // For full restoration, we'd need to implement custom navigation state management
        
        logger.info("Navigation state restored - tab: \(selectedTab.displayName)")
    }
    
    // MARK: - Navigation Utilities
    func getCurrentNavigationPath() -> NavigationPath {
        switch selectedTab {
        case .map:
            return mapNavigationPath
        case .helm:
            return helmNavigationPath
        }
    }
    
    func getNavigationDepth() -> Int {
        getCurrentNavigationPath().count
    }
    
    func isAtRootLevel() -> Bool {
        getNavigationDepth() == 0
    }
}

// MARK: - Supporting Data Models
struct NavigationManagerState: Equatable {
    let selectedTab: TabRoute
    let mapPathCount: Int
    let helmPathCount: Int
    
    var totalNavigationDepth: Int {
        mapPathCount + helmPathCount
    }
}

private struct NavigationStateData: Codable {
    let selectedTab: String
    let mapPathCount: Int
    let helmPathCount: Int
}

// MARK: - Navigation Extensions
extension NavigationManager {
    /// Generate deep link URL for current navigation state
    func generateDeepLink() -> URL? {
        var components = URLComponents()
        components.scheme = "waypoint"
        
        switch selectedTab {
        case .map:
            components.host = "map"
            if mapNavigationPath.count > 0 {
                components.path = "/current"
            }
        case .helm:
            components.host = "helm"
            if helmNavigationPath.count > 0 {
                components.path = "/current"
            }
        }
        
        return components.url
    }
    
    /// Check if a specific route is currently in the navigation stack
    func isRouteActive(_ route: AppRoute) -> Bool {
        // This is limited by NavigationPath's opaque nature
        // In a production app, you might want to maintain your own navigation state
        return false
    }
}