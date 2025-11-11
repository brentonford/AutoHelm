import Foundation
import CoreLocation
import Combine

@MainActor
class WaypointManager: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    @Published var selectedWaypoint: Waypoint?
    @Published var isLoadingWaypoints: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let waypointSubject = PassthroughSubject<[Waypoint], Never>()
    private let saveSubject = PassthroughSubject<Waypoint, Never>()
    
    // Publishers for reactive waypoint management
    var waypointsPublisher: AnyPublisher<[Waypoint], Never> {
        waypointSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    var waypointCountPublisher: AnyPublisher<Int, Never> {
        waypointsPublisher
            .map { $0.count }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // Recent waypoints (last 7 days)
    var recentWaypointsPublisher: AnyPublisher<[Waypoint], Never> {
        waypointsPublisher
            .map { waypoints in
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return waypoints.filter { $0.createdDate >= sevenDaysAgo }
                    .sorted { $0.createdDate > $1.createdDate }
            }
            .eraseToAnyPublisher()
    }
    
    // Waypoints within a specific region
    func waypointsInRegion(_ region: CLCircularRegion) -> AnyPublisher<[Waypoint], Never> {
        waypointsPublisher
            .map { waypoints in
                waypoints.filter { waypoint in
                    let location = CLLocation(latitude: waypoint.coordinate.latitude,
                                            longitude: waypoint.coordinate.longitude)
                    return region.contains(location.coordinate)
                }
            }
            .eraseToAnyPublisher()
    }
    
    init() {
        setupReactiveDataPipeline()
        loadWaypoints()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupReactiveDataPipeline() {
        // Debounced waypoint updates
        waypointSubject
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] waypoints in
                self?.waypoints = waypoints
            }
            .store(in: &cancellables)
        
        // Auto-save waypoints when changes occur
        saveSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] waypoint in
                self?.performSave(waypoint)
            }
            .store(in: &cancellables)
        
        // Automatic backup every 5 minutes if waypoints exist
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .filter { [weak self] _ in
                !(self?.waypoints.isEmpty ?? true)
            }
            .sink { [weak self] _ in
                self?.saveWaypoints()
            }
            .store(in: &cancellables)
        
        // Monitor waypoint count changes
        waypointCountPublisher
            .sink { count in
                print("Waypoint count updated: \(count)")
            }
            .store(in: &cancellables)
    }
    
    func saveWaypoint(_ waypoint: Waypoint) {
        var updatedWaypoints = waypoints
        
        if let index = updatedWaypoints.firstIndex(where: { $0.id == waypoint.id }) {
            var updatedWaypoint = waypoint
            updatedWaypoint.updateLastModified()
            updatedWaypoints[index] = updatedWaypoint
        } else {
            updatedWaypoints.append(waypoint)
        }
        
        waypointSubject.send(updatedWaypoints)
        saveSubject.send(waypoint)
    }
    
    func deleteWaypoint(id: UUID) {
        let filteredWaypoints = waypoints.filter { $0.id != id }
        waypointSubject.send(filteredWaypoints)
        saveWaypoints()
    }
    
    func deleteWaypoint(_ waypoint: Waypoint) {
        deleteWaypoint(id: waypoint.id)
    }
    
    func updateWaypoint(id: UUID, name: String? = nil, comments: String? = nil, iconName: String? = nil) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedWaypoint = waypoints[index]
        if let name = name { updatedWaypoint.name = name }
        if let comments = comments { updatedWaypoint.comments = comments }
        if let iconName = iconName { updatedWaypoint.iconName = iconName }
        updatedWaypoint.updateLastModified()
        
        var updatedWaypoints = waypoints
        updatedWaypoints[index] = updatedWaypoint
        
        waypointSubject.send(updatedWaypoints)
        saveSubject.send(updatedWaypoint)
    }
    
    func createWaypoint(at coordinate: CLLocationCoordinate2D, name: String? = nil) -> Waypoint {
        let waypointName = name ?? "Waypoint \(waypoints.count + 1)"
        let waypoint = Waypoint(coordinate: coordinate, name: waypointName)
        saveWaypoint(waypoint)
        return waypoint
    }
    
    func findNearbyWaypoints(to coordinate: CLLocationCoordinate2D, within radius: Double = 1000) -> [Waypoint] {
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return waypoints.filter { waypoint in
            let waypointLocation = CLLocation(latitude: waypoint.coordinate.latitude,
                                            longitude: waypoint.coordinate.longitude)
            return targetLocation.distance(from: waypointLocation) <= radius
        }.sorted { waypoint1, waypoint2 in
            let location1 = CLLocation(latitude: waypoint1.coordinate.latitude,
                                     longitude: waypoint1.coordinate.longitude)
            let location2 = CLLocation(latitude: waypoint2.coordinate.latitude,
                                     longitude: waypoint2.coordinate.longitude)
            return targetLocation.distance(from: location1) < targetLocation.distance(from: location2)
        }
    }
    
    func clearAllWaypoints() {
        waypointSubject.send([])
        saveWaypoints()
    }
    
    private func performSave(_ waypoint: Waypoint) {
        // Perform actual save operation
        saveWaypoints()
        print("Auto-saved waypoint: \(waypoint.name)")
    }
    
    private func saveWaypoints() {
        do {
            let data = try JSONEncoder().encode(waypoints)
            UserDefaults.standard.set(data, forKey: "SavedWaypoints")
        } catch {
            print("Failed to save waypoints: \(error)")
        }
    }
    
    private func loadWaypoints() {
        isLoadingWaypoints = true
        
        Just(())
            .delay(for: .milliseconds(100), scheduler: RunLoop.main)
            .map { _ -> [Waypoint] in
                guard let data = UserDefaults.standard.data(forKey: "SavedWaypoints"),
                      let savedWaypoints = try? JSONDecoder().decode([Waypoint].self, from: data) else {
                    return []
                }
                return savedWaypoints
            }
            .sink { [weak self] waypoints in
                self?.isLoadingWaypoints = false
                self?.waypointSubject.send(waypoints)
            }
            .store(in: &cancellables)
    }
}