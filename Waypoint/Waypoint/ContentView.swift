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
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var offlineTileManager = OfflineTileManager()
    @StateObject private var clusteringManager = AnnotationClusteringManager()
    
    private let logger = AppLogger.shared
    
    var body: some View {
        TabView(selection: $navigationManager.selectedTab) {
            NavigationStack(path: $navigationManager.mapNavigationPath) {
                MapView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem {
                Image(systemName: TabRoute.map.systemImage)
                Text(TabRoute.map.displayName)
            }
            .tag(TabRoute.map)
            
            NavigationStack(path: $navigationManager.helmNavigationPath) {
                HelmControlView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem {
                Image(systemName: TabRoute.helm.systemImage)
                Text(TabRoute.helm.displayName)
            }
            .tag(TabRoute.helm)
        }
        .environmentObject(bluetoothManager)
        .environmentObject(navigationManager)
        .environmentObject(offlineTileManager)
        .environmentObject(clusteringManager)
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onAppear {
            logger.info("App launched successfully", category: .general)
        }
    }
    
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .waypointDetail(let waypoint):
            WaypointDetailView(waypoint: waypoint, onSend: { coordinate in
                bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }, onDelete: { _ in
                navigationManager.popLast()
            })
            
        case .waypointList:
            WaypointListView(waypoints: [], onSend: { waypoint in
                bluetoothManager.sendWaypoint(latitude: waypoint.coordinate.latitude, longitude: waypoint.coordinate.longitude)
            }, onDelete: { _ in }, onEdit: { waypoint in
                navigationManager.navigateToWaypointDetail(waypoint)
            })
            
        case .settings:
            SettingsView()
            
        case .bluetoothSettings:
            BluetoothSettingsView()
            
        case .about:
            AboutView()
            
        default:
            Text("Feature coming soon")
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        let handled = navigationManager.handleDeepLink(url)
        logger.info("Deep link handled: \(handled) - \(url.absoluteString)", category: .navigation)
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothManager())
}