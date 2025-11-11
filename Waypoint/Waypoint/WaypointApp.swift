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
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var stateConnector = StateConnector.shared
    private let logger = AppLogger.shared
    
    init() {
        setupLogging()
        setupFrameworks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(networkManager)
                .environmentObject(stateConnector)
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
    
    private func setupFrameworks() {
        // Register managers with state connector for centralized state management
        stateConnector.register(bluetoothManager: bluetoothManager)
        stateConnector.register(networkManager: networkManager)
        
        logger.info("Enhanced frameworks initialized", category: .general)
    }
}