import Foundation
import Combine
import SwiftUI
import CoreLocation

@MainActor
class DataStore: ObservableObject {

    static let shared = DataStore()

    @Published var calibration: CompassCalibration = CompassCalibration()
    @Published var spotLockSettings: SpotLockSettings = SpotLockSettings()
    @Published var navSettings: NavSettings = NavSettings()
    @Published private(set) var lastError: String?

    private let calibrationKey = "compassCalibration"
    private let spotLockSettingsKey = "spotLockSettings"
    private let navSettingsKey = "navSettings"

    private init() {
        loadCalibration()
        loadSpotLockSettings()
        loadNavSettings()
    }

    // MARK: - Calibration

    @discardableResult
    func saveCalibration() -> Bool {
        do {
            let data = try JSONEncoder().encode(calibration)
            UserDefaults.standard.set(data, forKey: calibrationKey)
            lastError = nil
            print("[DataStore] Calibration saved successfully")
            return true
        } catch {
            let errorMessage = "Failed to save calibration: \(error.localizedDescription)"
            print("[DataStore] \(errorMessage)")
            lastError = errorMessage
            return false
        }
    }

    @discardableResult
    func loadCalibration() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey) else {
            print("[DataStore] No calibration data found in UserDefaults")
            return false
        }
        do {
            calibration = try JSONDecoder().decode(CompassCalibration.self, from: data)
            lastError = nil
            print("[DataStore] Calibration loaded successfully: \(calibration.sampleCount) samples")
            return true
        } catch {
            let errorMessage = "Failed to load calibration: \(error.localizedDescription)"
            print("[DataStore] \(errorMessage)")
            lastError = errorMessage
            // Reset to default calibration on load failure
            calibration = CompassCalibration()
            return false
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

    // MARK: - Spot Lock Settings

    func updateSpotLockSettings(_ settings: SpotLockSettings) {
        spotLockSettings = settings
        saveSpotLockSettings()
    }

    @discardableResult
    func saveSpotLockSettings() -> Bool {
        do {
            let data = try JSONEncoder().encode(spotLockSettings)
            UserDefaults.standard.set(data, forKey: spotLockSettingsKey)
            print("[DataStore] Spot Lock settings saved")
            return true
        } catch {
            print("[DataStore] Failed to save spot lock settings: \(error)")
            return false
        }
    }

    @discardableResult
    func loadSpotLockSettings() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: spotLockSettingsKey) else {
            return false
        }
        do {
            spotLockSettings = try JSONDecoder().decode(SpotLockSettings.self, from: data)
            print("[DataStore] Spot Lock settings loaded")
            return true
        } catch {
            print("[DataStore] Failed to load spot lock settings: \(error)")
            spotLockSettings = SpotLockSettings()
            return false
        }
    }

    // MARK: - Nav Settings

    func updateNavSettings(_ settings: NavSettings) {
        navSettings = settings
        saveNavSettings()
    }

    @discardableResult
    func saveNavSettings() -> Bool {
        do {
            let data = try JSONEncoder().encode(navSettings)
            UserDefaults.standard.set(data, forKey: navSettingsKey)
            print("[DataStore] Nav settings saved")
            return true
        } catch {
            print("[DataStore] Failed to save nav settings: \(error)")
            return false
        }
    }

    @discardableResult
    func loadNavSettings() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: navSettingsKey) else {
            return false
        }
        do {
            navSettings = try JSONDecoder().decode(NavSettings.self, from: data)
            print("[DataStore] Nav settings loaded")
            return true
        } catch {
            print("[DataStore] Failed to load nav settings: \(error)")
            navSettings = NavSettings()
            return false
        }
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
            headingOffset: 0.0,
            dateCalibrated: Date(),
            sampleCount: samples ?? 0
        )
    }
}