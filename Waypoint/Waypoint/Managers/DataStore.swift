import Foundation
import Combine
import SwiftUI
import CoreLocation

@MainActor
class DataStore: ObservableObject {
    
    static let shared = DataStore()
    
    @Published var waypoints: [Waypoint] = []
    @Published var calibration: CompassCalibration = CompassCalibration()
    
    private let waypointsKey = "savedWaypoints"
    private let calibrationKey = "compassCalibration"
    
    private init() {
        loadWaypoints()
        loadCalibration()
    }
    
    // MARK: - Waypoints
    
    func saveWaypoints() {
        do {
            let data = try JSONEncoder().encode(waypoints)
            UserDefaults.standard.set(data, forKey: waypointsKey)
        } catch {
            print("Failed to save waypoints: \(error)")
        }
    }
    
    func loadWaypoints() {
        guard let data = UserDefaults.standard.data(forKey: waypointsKey) else { return }
        do {
            waypoints = try JSONDecoder().decode([Waypoint].self, from: data)
        } catch {
            print("Failed to load waypoints: \(error)")
        }
    }
    
    func addWaypoint(_ waypoint: Waypoint) {
        waypoints.append(waypoint)
        saveWaypoints()
    }
    
    func updateWaypoint(_ waypoint: Waypoint) {
        guard let index = waypoints.firstIndex(where: { $0.id == waypoint.id }) else { return }
        waypoints[index] = waypoint
        saveWaypoints()
    }
    
    func deleteWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        saveWaypoints()
    }
    
    func deleteWaypoint(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        saveWaypoints()
    }
    
    // MARK: - Calibration
    
    func saveCalibration() {
        do {
            let data = try JSONEncoder().encode(calibration)
            UserDefaults.standard.set(data, forKey: calibrationKey)
        } catch {
            print("Failed to save calibration: \(error)")
        }
    }
    
    func loadCalibration() {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey) else { return }
        do {
            calibration = try JSONDecoder().decode(CompassCalibration.self, from: data)
        } catch {
            print("Failed to load calibration: \(error)")
        }
    }
    
    func updateCalibration(_ cal: CompassCalibration) {
        calibration = cal
        saveCalibration()
    }
    
    func clearCalibration() {
        calibration = CompassCalibration()
        saveCalibration()
    }
}

// MARK: - Compass Calibration Model

struct CompassCalibration: Codable, Equatable {
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0
    var offsetZ: Double = 0.0
    var scaleX: Double = 1.0
    var scaleY: Double = 1.0
    var scaleZ: Double = 1.0
    var headingOffset: Double = 0.0
    var dateCalibrated: Date?
    var sampleCount: Int = 0
    
    var isCalibrated: Bool {
        dateCalibrated != nil && sampleCount > 0
    }
    
    func toCommandString() -> String {
        String(format: "CAL_VALUES:%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.1f",
               offsetX, offsetY, offsetZ, scaleX, scaleY, scaleZ, headingOffset)
    }
}

// MARK: - Calibration Data (from device streaming)

struct CalibrationData: Codable {
    let cal: Bool?
    let samples: Int?
    let minX: Double?
    let maxX: Double?
    let minY: Double?
    let maxY: Double?
    let minZ: Double?
    let maxZ: Double?
    let rawX: Double?
    let rawY: Double?
    let rawZ: Double?
    
    var offsetX: Double {
        guard let minX, let maxX else { return 0 }
        return (maxX + minX) / 2.0
    }
    
    var offsetY: Double {
        guard let minY, let maxY else { return 0 }
        return (maxY + minY) / 2.0
    }
    
    var offsetZ: Double {
        guard let minZ, let maxZ else { return 0 }
        return (maxZ + minZ) / 2.0
    }
    
    var scaleX: Double {
        guard let minX, let maxX else { return 1 }
        let avgDeltaX = (maxX - minX) / 2.0
        let avgDelta = averageDelta
        return avgDeltaX != 0 ? avgDelta / avgDeltaX : 1.0
    }
    
    var scaleY: Double {
        guard let minY, let maxY else { return 1 }
        let avgDeltaY = (maxY - minY) / 2.0
        let avgDelta = averageDelta
        return avgDeltaY != 0 ? avgDelta / avgDeltaY : 1.0
    }
    
    var scaleZ: Double {
        guard let minZ, let maxZ else { return 1 }
        let avgDeltaZ = (maxZ - minZ) / 2.0
        let avgDelta = averageDelta
        return avgDeltaZ != 0 ? avgDelta / avgDeltaZ : 1.0
    }
    
    private var averageDelta: Double {
        guard let minX, let maxX, let minY, let maxY, let minZ, let maxZ else { return 1 }
        let avgDeltaX = (maxX - minX) / 2.0
        let avgDeltaY = (maxY - minY) / 2.0
        let avgDeltaZ = (maxZ - minZ) / 2.0
        return (avgDeltaX + avgDeltaY + avgDeltaZ) / 3.0
    }
    
    func toCalibration() -> CompassCalibration {
        CompassCalibration(
            offsetX: offsetX,
            offsetY: offsetY,
            offsetZ: offsetZ,
            scaleX: scaleX,
            scaleY: scaleY,
            scaleZ: scaleZ,
            headingOffset: 0.0,  // Don't set headingOffset from magnetometer calibration
            dateCalibrated: Date(),
            sampleCount: samples ?? 0
        )
    }
}