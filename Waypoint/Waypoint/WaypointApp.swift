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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
}