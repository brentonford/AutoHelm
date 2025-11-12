import Foundation
import CoreLocation

struct Waypoint: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    var name: String
    var comments: String
    var photoData: Data?
    var iconName: String
    let createdDate: Date
    var lastUpdatedDate: Date
    
    init(coordinate: CLLocationCoordinate2D, name: String = "Waypoint", comments: String = "", iconName: String = "mappin.circle.fill") {
        self.id = UUID()
        self.coordinate = coordinate
        self.name = name
        self.comments = comments
        self.photoData = nil
        self.iconName = iconName
        self.createdDate = Date()
        self.lastUpdatedDate = Date()
    }
    
    mutating func updateLastModified() {
        self.lastUpdatedDate = Date()
    }
    
    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CLLocationCoordinate2D: Codable, @retroactive Equatable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return abs(lhs.latitude - rhs.latitude) < 0.000001 && 
               abs(lhs.longitude - rhs.longitude) < 0.000001
    }
    
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

struct DeviceStatus: Codable, Equatable {
    let hasFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let speedKnots: Double?
    let time: String?
    let date: String?
    let hdop: Double?
    let vdop: Double?
    let pdop: Double?
    let heading: Double
    let distance: Double
    let bearing: Double
    let targetLat: Double?
    let targetLon: Double?
    
    private enum CodingKeys: String, CodingKey {
        case hasFix = "has_fix"
        case satellites
        case currentLat
        case currentLon
        case altitude
        case speedKnots = "speed_knots"
        case time
        case date
        case hdop
        case vdop
        case pdop
        case heading
        case distance
        case bearing
        case targetLat
        case targetLon
    }
    
    var currentCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
    }
    
    var targetCoordinate: CLLocationCoordinate2D? {
        guard let lat = targetLat, let lon = targetLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var hasGpsFix: Bool {
        return hasFix
    }
    
    var gpsAccuracyDescription: String {
        guard let hdop = hdop else { return "Unknown" }
        
        switch hdop {
        case 0..<1:
            return "Excellent"
        case 1..<2:
            return "Good"
        case 2..<5:
            return "Moderate"
        case 5..<10:
            return "Fair"
        case 10..<20:
            return "Poor"
        default:
            return "Very Poor"
        }
    }
}

// MARK: - Enhanced JSON Parsing Extensions
extension DeviceStatus {
    /// Creates a DeviceStatus from JSON data with robust error handling
    static func fromJSONData(_ data: Data) -> DeviceStatus? {
        do {
            let decoder = JSONDecoder()
            // Use default keys since we have custom CodingKeys mapping
            return try decoder.decode(DeviceStatus.self, from: data)
        } catch DecodingError.keyNotFound(let key, let context) {
            print("DeviceStatus JSON parsing error - missing key: \(key.stringValue)")
            print("Context: \(context.debugDescription)")
            return nil
        } catch DecodingError.typeMismatch(let type, let context) {
            print("DeviceStatus JSON parsing error - type mismatch for type: \(type)")
            print("Context: \(context.debugDescription)")
            return nil
        } catch DecodingError.valueNotFound(let type, let context) {
            print("DeviceStatus JSON parsing error - value not found for type: \(type)")
            print("Context: \(context.debugDescription)")
            return nil
        } catch DecodingError.dataCorrupted(let context) {
            print("DeviceStatus JSON parsing error - data corrupted")
            print("Context: \(context.debugDescription)")
            return nil
        } catch {
            print("DeviceStatus JSON parsing error - unknown error: \(error)")
            return nil
        }
    }
    
    /// Creates a DeviceStatus from JSON string with robust error handling
    static func fromJSONString(_ jsonString: String) -> DeviceStatus? {
        guard let data = jsonString.data(using: .utf8) else {
            print("DeviceStatus JSON parsing error - invalid UTF8 string")
            return nil
        }
        
        // Try standard JSON parsing first
        if let status = fromJSONData(data) {
            return status
        }
        
        // Fallback to manual parsing for malformed JSON
        return tryManualParsing(jsonString)
    }
    
    
    private static func tryManualParsing(_ jsonString: String) -> DeviceStatus? {
        // Check if JSON is truncated or incomplete
        guard jsonString.contains("}") else {
            print("JSON appears truncated - missing closing brace")
            return nil
        }
        
        // Find the last complete JSON object if multiple are concatenated
        var cleanedJson = extractLastCompleteJSON(jsonString)
        
        // Apply corruption fixes
        cleanedJson = fixCorruptedJSON(cleanedJson)
        
        // Parse JSON manually to handle unexpected formats
        guard let jsonData = cleanedJson.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("Failed to parse JSON as dictionary")
            return nil
        }
        
        // Extract required fields with fallbacks and corruption handling
        let hasFix: Bool = {
            // Try direct boolean first
            if let boolValue = jsonDict["has_fix"] as? Bool {
                return boolValue
            }
            // Try alternative keys
            if let boolValue = jsonDict["hasGpsFix"] as? Bool {
                return boolValue
            }
            if let boolValue = jsonDict["hasFix"] as? Bool {
                return boolValue
            }
            // Handle corrupted boolean as string
            if let stringValue = jsonDict["has_fix"] as? String {
                if stringValue.hasPrefix("true") {
                    return true
                } else if stringValue.hasPrefix("false") {
                    return false
                }
            }
            return false
        }()
        
        let satellites = jsonDict["satellites"] as? Int ?? 0
        
        let currentLat = jsonDict["currentLat"] as? Double ??
                        jsonDict["current_lat"] as? Double ?? 0.0
        
        let currentLon = jsonDict["currentLon"] as? Double ??
                        jsonDict["current_lon"] as? Double ?? 0.0
        
        let altitude = jsonDict["altitude"] as? Double ?? 0.0
        let heading = jsonDict["heading"] as? Double ?? 0.0
        let distance = jsonDict["distance"] as? Double ?? 0.0
        let bearing = jsonDict["bearing"] as? Double ?? 0.0
        
        let speedKnots = jsonDict["speed_knots"] as? Double ??
                        jsonDict["speedKnots"] as? Double
        
        let time = jsonDict["time"] as? String
        let date = jsonDict["date"] as? String
        
        let hdop = jsonDict["hdop"] as? Double
        let vdop = jsonDict["vdop"] as? Double
        let pdop = jsonDict["pdop"] as? Double
        
        let targetLat = jsonDict["targetLat"] as? Double ??
                       jsonDict["target_lat"] as? Double
        
        let targetLon = jsonDict["targetLon"] as? Double ??
                       jsonDict["target_lon"] as? Double
        
        return DeviceStatus(
            hasFix: hasFix,
            satellites: satellites,
            currentLat: currentLat,
            currentLon: currentLon,
            altitude: altitude,
            speedKnots: speedKnots,
            time: time,
            date: date,
            hdop: hdop,
            vdop: vdop,
            pdop: pdop,
            heading: heading,
            distance: distance,
            bearing: bearing,
            targetLat: targetLat,
            targetLon: targetLon
        )
    }
    
    /// Type-safe property access with fallback values
    var safeCurrentCoordinate: CLLocationCoordinate2D {
        let lat = currentLat.isFinite ? currentLat : 0.0
        let lon = currentLon.isFinite ? currentLon : 0.0
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var safeTargetCoordinate: CLLocationCoordinate2D? {
        guard let lat = targetLat, let lon = targetLon,
              lat.isFinite, lon.isFinite else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Validates GPS coordinate ranges
    var hasValidCoordinates: Bool {
        return currentLat >= -90 && currentLat <= 90 &&
               currentLon >= -180 && currentLon <= 180 &&
               currentLat.isFinite && currentLon.isFinite
    }
    
    /// Extracts the last complete JSON object from potentially concatenated or truncated data
    private static func extractLastCompleteJSON(_ input: String) -> String {
        // Remove any leading/trailing whitespace and newlines
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find all complete JSON objects (those that start with { and end with })
        var braceCount = 0
        var lastCompleteEnd = -1
        var lastCompleteStart = -1
        
        for (index, char) in cleaned.enumerated() {
            if char == "{" {
                if braceCount == 0 {
                    lastCompleteStart = index
                }
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    lastCompleteEnd = index
                }
            }
        }
        
        // Return the last complete JSON object if found
        if lastCompleteStart >= 0 && lastCompleteEnd > lastCompleteStart {
            let startIndex = cleaned.index(cleaned.startIndex, offsetBy: lastCompleteStart)
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: lastCompleteEnd + 1)
            return String(cleaned[startIndex..<endIndex])
        }
        
        // If no complete JSON found, return the original cleaned string
        return cleaned
    }
    
    /// Fixes common JSON corruption patterns
    private static func fixCorruptedJSON(_ jsonString: String) -> String {
        var fixed = jsonString
        
        // Fix corrupted boolean values like "false.9" -> "false"
        fixed = fixed.replacingOccurrences(
            of: #"false\.[0-9]+"#,
            with: "false",
            options: .regularExpression
        )
        fixed = fixed.replacingOccurrences(
            of: #"true\.[0-9]+"#,
            with: "true",
            options: .regularExpression
        )
        
        // Fix corrupted null values like "null.0" -> "null"
        fixed = fixed.replacingOccurrences(
            of: #"null\.[0-9]+"#,
            with: "null",
            options: .regularExpression
        )
        
        // Fix multiple decimal points in numbers
        fixed = fixed.replacingOccurrences(
            of: #"([0-9]+)\.+([0-9]+)"#,
            with: "$1.$2",
            options: .regularExpression
        )
        
        // Remove any trailing garbage after JSON closing brace
        if let lastBraceIndex = fixed.lastIndex(of: "}") {
            fixed = String(fixed[...lastBraceIndex])
        }
        
        return fixed
    }
}

enum AppNavigationState: Equatable, Codable {
    case idle
    case navigating
    case arrived
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .navigating:
            return "Navigating"
        case .arrived:
            return "Arrived"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    static func == (lhs: AppNavigationState, rhs: AppNavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.navigating, .navigating), (.arrived, .arrived):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

struct SystemConfig {
    static let maxWaypoints: Int = 50
    static let waypointArrivalDistance: Double = 5.0 // meters
    static let coordinatePrecision: Int = 6
    static let autoSaveInterval: TimeInterval = 30.0 // seconds
    
    static func formatCoordinate(_ value: Double) -> String {
        return String(format: "%.\(coordinatePrecision)f", value)
    }
}

// MARK: - UserDefaults Property Wrappers
@propertyWrapper
struct UserDefault<T: Codable> {
    let key: String
    let defaultValue: T
    private let userDefaults: UserDefaults
    
    init(key: String, defaultValue: T, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults
    }
    
    var wrappedValue: T {
        get {
            guard let data = userDefaults.data(forKey: key) else {
                return defaultValue
            }
            
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("UserDefault decoding error for key '\(key)': \(error)")
                return defaultValue
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                userDefaults.set(data, forKey: key)
            } catch {
                print("UserDefault encoding error for key '\(key)': \(error)")
            }
        }
    }
}

@propertyWrapper
struct UserDefaultArray<T: Codable> {
    let key: String
    let defaultValue: [T]
    private let userDefaults: UserDefaults
    
    init(key: String, defaultValue: [T] = [], userDefaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults
    }
    
    var wrappedValue: [T] {
        get {
            guard let data = userDefaults.data(forKey: key) else {
                return defaultValue
            }
            
            do {
                return try JSONDecoder().decode([T].self, from: data)
            } catch {
                print("UserDefaultArray decoding error for key '\(key)': \(error)")
                return defaultValue
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                userDefaults.set(data, forKey: key)
            } catch {
                print("UserDefaultArray encoding error for key '\(key)': \(error)")
            }
        }
    }
    
    var projectedValue: UserDefaultArrayBinding<T> {
        UserDefaultArrayBinding(wrapper: self)
    }
}

struct UserDefaultArrayBinding<T: Codable> {
    private var wrapper: UserDefaultArray<T>
    
    init(wrapper: UserDefaultArray<T>) {
        self.wrapper = wrapper
    }
    
    mutating func append(_ element: T) {
        var array = wrapper.wrappedValue
        array.append(element)
        wrapper.wrappedValue = array
    }
    
    mutating func remove(at index: Int) {
        var array = wrapper.wrappedValue
        guard index < array.count else { return }
        array.remove(at: index)
        wrapper.wrappedValue = array
    }
    
    mutating func removeAll(where predicate: (T) -> Bool) {
        var array = wrapper.wrappedValue
        array.removeAll(where: predicate)
        wrapper.wrappedValue = array
    }
}