import Foundation
import OSLog
import Network
import Combine
import UIKit

// MARK: - Log Levels
enum LogLevel: String, CaseIterable, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Log Categories
enum LogCategory: String, CaseIterable, Codable {
    case general = "General"
    case navigation = "Navigation"
    case bluetooth = "Bluetooth"
    case location = "Location"
    case waypoints = "Waypoints"
    case mapkit = "MapKit"
    case networking = "Networking"
    case performance = "Performance"
    case ui = "UI"
    
    var subsystem: String {
        return "com.waypoint.app"
    }
}

// MARK: - Performance Metrics
struct PerformanceMetrics {
    let category: LogCategory
    let operation: String
    let duration: TimeInterval
    let timestamp: Date
    let additionalInfo: [String: Any]?
    
    init(category: LogCategory, operation: String, duration: TimeInterval, additionalInfo: [String: Any]? = nil) {
        self.category = category
        self.operation = operation
        self.duration = duration
        self.timestamp = Date()
        self.additionalInfo = additionalInfo
    }
}

// MARK: - Remote Logging Configuration
struct RemoteLoggingConfig {
    let endpoint: URL
    let apiKey: String
    let batchSize: Int
    let flushInterval: TimeInterval
    let enabledLevels: Set<LogLevel>
    
    static let disabled = RemoteLoggingConfig(
        endpoint: URL(string: "https://disabled.com")!,
        apiKey: "",
        batchSize: 0,
        flushInterval: 0,
        enabledLevels: []
    )
}

// MARK: - App Logger
@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()
    
    private let osLogger: OSLog
    private var performanceMetrics: [PerformanceMetrics] = []
    private var logBuffer: [LogEntry] = []
    private var remoteConfig: RemoteLoggingConfig = .disabled
    
    @Published var isRemoteLoggingEnabled: Bool = false
    @Published var currentLogLevel: LogLevel = .info
    
    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = false
    
    // Performance measurement
    private var performanceTimers: [String: Date] = [:]
    
    init() {
        self.osLogger = OSLog(subsystem: LogCategory.general.subsystem, category: LogCategory.general.rawValue)
        setupRemoteLogging()
        setupNetworkMonitoring()
        loadConfiguration()
    }
    
    deinit {
        networkMonitor.cancel()
        cancellables.removeAll()
    }
    
    // MARK: - Configuration
    private func loadConfiguration() {
        // Load logging configuration from UserDefaults or remote config
        if let savedLevel = UserDefaults.standard.object(forKey: "LogLevel") as? String,
           let level = LogLevel(rawValue: savedLevel) {
            currentLogLevel = level
        }
        
        isRemoteLoggingEnabled = UserDefaults.standard.bool(forKey: "RemoteLoggingEnabled")
    }
    
    func configureRemoteLogging(_ config: RemoteLoggingConfig) {
        self.remoteConfig = config
        self.isRemoteLoggingEnabled = config.endpoint.absoluteString != "https://disabled.com"
        UserDefaults.standard.set(isRemoteLoggingEnabled, forKey: "RemoteLoggingEnabled")
        
        if isRemoteLoggingEnabled {
            startRemoteLogging()
        }
    }
    
    func setLogLevel(_ level: LogLevel) {
        currentLogLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "LogLevel")
        info("Log level changed to: \(level.rawValue)", category: .general)
    }
    
    // MARK: - Core Logging Methods
    func debug(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, error: Error? = nil, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(level: .error, message: fullMessage, category: category, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, error: Error? = nil, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(level: .critical, message: fullMessage, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Structured Logging
    func logWithMetadata(_ level: LogLevel, _ message: String, metadata: [String: Any], category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let fullMessage = "\(message) [\(metadataString)]"
        log(level: level, message: fullMessage, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Performance Logging
    func startPerformanceMeasurement(_ operation: String, category: LogCategory = .performance) {
        let key = "\(category.rawValue).\(operation)"
        performanceTimers[key] = Date()
        debug("Started performance measurement: \(operation)", category: category)
    }
    
    func endPerformanceMeasurement(_ operation: String, category: LogCategory = .performance, additionalInfo: [String: Any]? = nil) {
        let key = "\(category.rawValue).\(operation)"
        
        guard let startTime = performanceTimers[key] else {
            warning("No start time found for performance measurement: \(operation)", category: category)
            return
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let metric = PerformanceMetrics(
            category: category,
            operation: operation,
            duration: duration,
            additionalInfo: additionalInfo
        )
        
        performanceMetrics.append(metric)
        performanceTimers.removeValue(forKey: key)
        
        info("Performance measurement completed: \(operation) took \(String(format: "%.3f", duration))s", category: category)
        
        // Clean up old metrics (keep last 100)
        if performanceMetrics.count > 100 {
            performanceMetrics.removeFirst(performanceMetrics.count - 100)
        }
    }
    
    func measurePerformance<T>(_ operation: String, category: LogCategory = .performance, block: () throws -> T) rethrows -> T {
        startPerformanceMeasurement(operation, category: category)
        defer { endPerformanceMeasurement(operation, category: category) }
        return try block()
    }
    
    func measurePerformanceAsync<T>(_ operation: String, category: LogCategory = .performance, block: () async throws -> T) async rethrows -> T {
        startPerformanceMeasurement(operation, category: category)
        defer { endPerformanceMeasurement(operation, category: category) }
        return try await block()
    }
    
    // MARK: - Core Logging Implementation
    private func log(level: LogLevel, message: String, category: LogCategory, file: String, function: String, line: Int) {
        guard shouldLog(level: level) else { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let formattedMessage = formatMessage(level: level, message: message, fileName: fileName, function: function, line: line)
        
        // OSLog
        let categoryLogger = OSLog(subsystem: category.subsystem, category: category.rawValue)
        os_log("%{public}@", log: categoryLogger, type: level.osLogType, formattedMessage)
        
        // Console output in debug builds
        #if DEBUG
        print("\(level.emoji) [\(category.rawValue)] \(formattedMessage)")
        #endif
        
        // Buffer for remote logging
        if isRemoteLoggingEnabled && remoteConfig.enabledLevels.contains(level) {
            let logEntry = LogEntry(
                level: level,
                category: category,
                message: message,
                fileName: fileName,
                function: function,
                line: line,
                timestamp: Date()
            )
            logBuffer.append(logEntry)
            
            if logBuffer.count >= remoteConfig.batchSize {
                flushRemoteLogs()
            }
        }
    }
    
    private func shouldLog(level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error, .critical]
        guard let currentIndex = levels.firstIndex(of: currentLogLevel),
              let levelIndex = levels.firstIndex(of: level) else {
            return true
        }
        return levelIndex >= currentIndex
    }
    
    private func formatMessage(level: LogLevel, message: String, fileName: String, function: String, line: Int) -> String {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        return "\(timestamp) [\(level.rawValue)] \(fileName):\(line) \(function) - \(message)"
    }
    
    // MARK: - Remote Logging
    private func setupRemoteLogging() {
        guard isRemoteLoggingEnabled else { return }
        startRemoteLogging()
    }
    
    private func startRemoteLogging() {
        // Auto-flush logs periodically
        Timer.publish(every: remoteConfig.flushInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.flushRemoteLogs()
                }
            }
            .store(in: &cancellables)
    }
    
    private func flushRemoteLogs() {
        guard isNetworkAvailable && !logBuffer.isEmpty else { return }
        
        let logsToSend = logBuffer
        logBuffer.removeAll()
        
        Task {
            do {
                try await sendLogsToRemote(logsToSend)
                debug("Successfully sent \(logsToSend.count) logs to remote server", category: .networking)
            } catch {
                // Return logs to buffer on failure
                await MainActor.run {
                    logBuffer.insert(contentsOf: logsToSend, at: 0)
                }
                warning("Failed to send logs to remote server", category: .networking)
            }
        }
    }
    
    private func sendLogsToRemote(_ logs: [LogEntry]) async throws {
        guard !remoteConfig.apiKey.isEmpty else { return }
        
        var request = URLRequest(url: remoteConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(remoteConfig.apiKey)", forHTTPHeaderField: "Authorization")
        
        let logData = RemoteLogBatch(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            logs: logs
        )
        
        request.httpBody = try JSONEncoder().encode(logData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw RemoteLoggingError.serverError(httpResponse.statusCode)
        }
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    // MARK: - Analytics and Reporting
    func getPerformanceReport() -> [PerformanceMetrics] {
        return performanceMetrics
    }
    
    func getAveragePerformance(for operation: String, category: LogCategory) -> TimeInterval? {
        let relevantMetrics = performanceMetrics.filter { 
            $0.operation == operation && $0.category == category 
        }
        
        guard !relevantMetrics.isEmpty else { return nil }
        
        let totalDuration = relevantMetrics.reduce(0) { $0 + $1.duration }
        return totalDuration / Double(relevantMetrics.count)
    }
    
    func clearPerformanceMetrics() {
        performanceMetrics.removeAll()
        info("Performance metrics cleared", category: .performance)
    }
}

// MARK: - Supporting Data Models
private struct LogEntry: Codable {
    let level: LogLevel
    let category: LogCategory
    let message: String
    let fileName: String
    let function: String
    let line: Int
    let timestamp: Date
}

private struct RemoteLogBatch: Codable {
    let appVersion: String
    let deviceModel: String
    let osVersion: String
    let logs: [LogEntry]
}

private enum RemoteLoggingError: Error {
    case serverError(Int)
    case networkUnavailable
    case invalidConfiguration
}

// MARK: - Extensions
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - Logger Extensions for Convenience
extension AppLogger {
    // Bluetooth-specific logging
    func bluetoothConnected(_ deviceName: String) {
        info("Bluetooth connected to device: \(deviceName)", category: .bluetooth)
    }
    
    func bluetoothDisconnected(_ deviceName: String, error: Error? = nil) {
        if let error = error {
            warning("Bluetooth disconnected from \(deviceName) with error: \(error.localizedDescription)", category: .bluetooth)
        } else {
            info("Bluetooth disconnected from device: \(deviceName)", category: .bluetooth)
        }
    }
    
    // Location-specific logging
    func locationUpdated(accuracy: Double, coordinate: String) {
        debug("Location updated - accuracy: \(accuracy)m, coordinate: \(coordinate)", category: .location)
    }
    
    func locationError(_ error: Error) {
        self.error("Location error occurred", error: error, category: .location)
    }
    
    // Waypoint-specific logging
    func waypointCreated(_ name: String, coordinate: String) {
        info("Waypoint created: \(name) at \(coordinate)", category: .waypoints)
    }
    
    func waypointSent(_ name: String, coordinate: String) {
        info("Waypoint sent to device: \(name) at \(coordinate)", category: .waypoints)
    }
    
    // Navigation-specific logging
    func navigationEvent(_ event: String, details: [String: Any] = [:]) {
        logWithMetadata(.info, event, metadata: details, category: .navigation)
    }
}