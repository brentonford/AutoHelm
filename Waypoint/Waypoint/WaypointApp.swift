//
//  WaypointApp.swift
//  Waypoint
//
//  Created by BRENTON FORD on 9/11/2025.
//

import SwiftUI

@main
struct WaypointApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    private let logger = AppLogger.shared
    
    init() {
        setupLogging()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
    
    private func setupLogging() {
        // Configure logging levels based on build configuration
        #if DEBUG
        logger.setLogLevel(.debug)
        #else
        logger.setLogLevel(.info)
        #endif
        
        logger.info("Waypoint app initializing", category: .general)
    }
}