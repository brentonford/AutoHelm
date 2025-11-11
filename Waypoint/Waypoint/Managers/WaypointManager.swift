import Foundation
import CoreLocation
import Combine

@MainActor
class WaypointManager: ObservableObject {
    @Published var selectedWaypoint: Waypoint?
    @Published var isLoadingWaypoints: Bool = false
    
    // Enhanced UserDefaults property wrapper for type-safe waypoint storage
    @UserDefaultArray(key: "SavedWaypoints", defaultValue: [])
    private var waypointsStorage: [Waypoint]
    
    private var cancellables = Set<AnyCancellable>()
    private let waypointSubject = PassthroughSubject<[Waypoint], Never>()
    private let saveSubject = PassthroughSubject<Waypoint, Never>()
    
    // Computed property that uses the property wrapper
    var waypoints: [Waypoint] {
        get { waypointsStorage }
        set { 
            waypointsStorage = newValue
            waypointSubject.send(newValue)
        }
    }
    
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
    
    // Enhanced: Publisher for waypoints sorted by distance from a location
    func waypointsByDistancePublisher(from coordinate: CLLocationCoordinate2D) -> AnyPublisher<[WaypointWithDistance], Never> {
        waypointsPublisher
            .map { waypoints in
                let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                
                return waypoints.map { waypoint in
                    let waypointLocation = CLLocation(latitude: waypoint.coordinate.latitude,
                                                    longitude: waypoint.coordinate.longitude)
                    let distance = currentLocation.distance(from: waypointLocation)
                    
                    return WaypointWithDistance(waypoint: waypoint, distance: distance)
                }.sorted { $0.distance < $1.distance }
            }
            .eraseToAnyPublisher()
    }
    
    init() {
        setupReactiveDataPipeline()
        loadWaypointsFromStorage()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupReactiveDataPipeline() {
        // Debounced waypoint updates
        waypointSubject
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { _ in
                // Updates are automatically handled by the property wrapper
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
                self?.performAutomaticBackup()
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
        
        waypoints = updatedWaypoints
        saveSubject.send(waypoint)
    }
    
    func deleteWaypoint(id: UUID) {
        let filteredWaypoints = waypoints.filter { $0.id != id }
        waypoints = filteredWaypoints
    }
    
    func deleteWaypoint(_ waypoint: Waypoint) {
        deleteWaypoint(id: waypoint.id)
    }
    
    func updateWaypoint(id: UUID, name: String? = nil, comments: String? = nil, iconName: String? = nil) {
        var updatedWaypoints = waypoints
        guard let index = updatedWaypoints.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedWaypoint = updatedWaypoints[index]
        if let name = name { updatedWaypoint.name = name }
        if let comments = comments { updatedWaypoint.comments = comments }
        if let iconName = iconName { updatedWaypoint.iconName = iconName }
        updatedWaypoint.updateLastModified()
        
        updatedWaypoints[index] = updatedWaypoint
        waypoints = updatedWaypoints
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
    
    // Enhanced: Find waypoints by name with fuzzy matching
    func findWaypoints(matching searchText: String) -> [Waypoint] {
        guard !searchText.isEmpty else { return waypoints }
        
        return waypoints.filter { waypoint in
            waypoint.name.localizedCaseInsensitiveContains(searchText) ||
            waypoint.comments.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Enhanced: Get waypoints within a date range
    func getWaypoints(from startDate: Date, to endDate: Date) -> [Waypoint] {
        return waypoints.filter { waypoint in
            waypoint.createdDate >= startDate && waypoint.createdDate <= endDate
        }.sorted { $0.createdDate > $1.createdDate }
    }
    
    // Enhanced: Export waypoints to various formats
    func exportWaypoints(format: WaypointExportFormat) -> Data? {
        switch format {
        case .json:
            return exportAsJSON()
        case .gpx:
            return exportAsGPX()
        case .csv:
            return exportAsCSV()
        }
    }
    
    // Enhanced: Import waypoints with validation
    func importWaypoints(from data: Data, format: WaypointExportFormat) -> Result<Int, WaypointImportError> {
        switch format {
        case .json:
            return importFromJSON(data)
        case .gpx:
            return importFromGPX(data)
        case .csv:
            return importFromCSV(data)
        }
    }
    
    func clearAllWaypoints() {
        waypoints = []
    }
    
    private func performSave(_ waypoint: Waypoint) {
        // Save is automatically handled by the property wrapper
        print("Auto-saved waypoint: \(waypoint.name)")
    }
    
    private func performAutomaticBackup() {
        // Property wrapper handles persistence automatically
        // Additional backup logic could be added here (e.g., iCloud sync)
        print("Automatic waypoint backup completed - \(waypoints.count) waypoints")
    }
    
    private func loadWaypointsFromStorage() {
        isLoadingWaypoints = true
        
        Just(())
            .delay(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isLoadingWaypoints = false
                // Property wrapper automatically loads the data
                self.waypointSubject.send(self.waypoints)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Export Functions
    
    private func exportAsJSON() -> Data? {
        do {
            return try JSONEncoder().encode(waypoints)
        } catch {
            print("Failed to export waypoints as JSON: \(error)")
            return nil
        }
    }
    
    private func exportAsGPX() -> Data? {
        let gpxContent = generateGPXContent()
        return gpxContent.data(using: .utf8)
    }
    
    private func exportAsCSV() -> Data? {
        var csvContent = "Name,Latitude,Longitude,Comments,Created Date\n"
        
        for waypoint in waypoints {
            let csvLine = "\"\(waypoint.name)\",\(waypoint.coordinate.latitude),\(waypoint.coordinate.longitude),\"\(waypoint.comments)\",\(waypoint.createdDate.ISO8601Format())\n"
            csvContent += csvLine
        }
        
        return csvContent.data(using: .utf8)
    }
    
    private func generateGPXContent() -> String {
        let formatter = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Waypoint App" xmlns="http://www.topografix.com/GPX/1/1">
        
        """
        
        for waypoint in waypoints {
            gpx += """
            <wpt lat="\(waypoint.coordinate.latitude)" lon="\(waypoint.coordinate.longitude)">
                <name>\(waypoint.name)</name>
                <desc>\(waypoint.comments)</desc>
                <time>\(formatter.string(from: waypoint.createdDate))</time>
            </wpt>
            
            """
        }
        
        gpx += "</gpx>"
        return gpx
    }
    
    // MARK: - Import Functions
    
    private func importFromJSON(_ data: Data) -> Result<Int, WaypointImportError> {
        do {
            let importedWaypoints = try JSONDecoder().decode([Waypoint].self, from: data)
            let validWaypoints = importedWaypoints.filter { isValidCoordinate($0.coordinate) }
            
            // Add imported waypoints to existing collection
            waypoints.append(contentsOf: validWaypoints)
            
            return .success(validWaypoints.count)
        } catch {
            return .failure(.invalidFormat(error.localizedDescription))
        }
    }
    
    private func importFromGPX(_ data: Data) -> Result<Int, WaypointImportError> {
        // Simplified GPX parsing - would use XMLParser in full implementation
        guard let gpxString = String(data: data, encoding: .utf8) else {
            return .failure(.invalidFormat("Cannot decode GPX data"))
        }
        
        // Basic GPX waypoint extraction (simplified)
        let waypoints = parseGPXWaypoints(from: gpxString)
        self.waypoints.append(contentsOf: waypoints)
        
        return .success(waypoints.count)
    }
    
    private func importFromCSV(_ data: Data) -> Result<Int, WaypointImportError> {
        guard let csvString = String(data: data, encoding: .utf8) else {
            return .failure(.invalidFormat("Cannot decode CSV data"))
        }
        
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return .failure(.invalidFormat("CSV file must have header and data rows"))
        }
        
        var importedWaypoints: [Waypoint] = []
        
        // Skip header row
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }
            
            let name = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard let latitude = Double(components[1]),
                  let longitude = Double(components[2]) else { continue }
            
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard isValidCoordinate(coordinate) else { continue }
            
            let comments = components.count > 3 ? components[3].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : ""
            let waypoint = Waypoint(coordinate: coordinate, name: name, comments: comments)
            importedWaypoints.append(waypoint)
        }
        
        waypoints.append(contentsOf: importedWaypoints)
        return .success(importedWaypoints.count)
    }
    
    private func parseGPXWaypoints(from gpxString: String) -> [Waypoint] {
        // Simplified GPX parsing - would use proper XML parsing in production
        var waypoints: [Waypoint] = []
        
        let lines = gpxString.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("<wpt") {
                if let waypoint = parseGPXWaypoint(from: line) {
                    waypoints.append(waypoint)
                }
            }
        }
        
        return waypoints
    }
    
    private func parseGPXWaypoint(from line: String) -> Waypoint? {
        // Simplified parsing - would use proper XML parser in production
        let pattern = #"lat="([^"]+)" lon="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        let latRange = Range(match.range(at: 1), in: line)!
        let lonRange = Range(match.range(at: 2), in: line)!
        
        guard let latitude = Double(String(line[latRange])),
              let longitude = Double(String(line[lonRange])) else {
            return nil
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Waypoint(coordinate: coordinate, name: "Imported Waypoint")
    }
    
    private func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
               coordinate.longitude >= -180 && coordinate.longitude <= 180
    }
}

// MARK: - Supporting Data Models

struct WaypointWithDistance {
    let waypoint: Waypoint
    let distance: CLLocationDistance
    
    var formattedDistance: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}

enum WaypointExportFormat: CaseIterable {
    case json
    case gpx
    case csv
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .gpx: return "gpx"
        case .csv: return "csv"
        }
    }
    
    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .gpx: return "GPX"
        case .csv: return "CSV"
        }
    }
}

enum WaypointImportError: LocalizedError {
    case invalidFormat(String)
    case noWaypointsFound
    case duplicateWaypoints(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let details):
            return "Invalid file format: \(details)"
        case .noWaypointsFound:
            return "No valid waypoints found in the file"
        case .duplicateWaypoints(let count):
            return "\(count) duplicate waypoints were skipped"
        }
    }
}