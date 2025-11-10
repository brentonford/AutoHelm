//
//  ContentView.swift
//  Waypoint
//
//  Created by BRENTON FORD on 9/11/2025.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Image(systemName: "map")
                    Text("Map")
                }
            
            HelmControlView()
                .tabItem {
                    Image(systemName: "helm")
                    Text("Helm")
                }
        }
        .environmentObject(bluetoothManager)
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothManager())
}