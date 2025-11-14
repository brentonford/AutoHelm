import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var waypointManager = WaypointManager()
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var offlineTileManager: OfflineTileManager
    @EnvironmentObject var clusteringManager: AnnotationClusteringManager
    @EnvironmentObject var navigationManager: NavigationManager
    
    private let logger = AppLogger.shared
    @State private var position: MapCameraPosition = .automatic
    @State private var mapType: MKMapType = .standard
    @State private var isLoadingSatellite: Bool = false
    @State private var selectedWaypoint: Waypoint?
    @State private var showingWaypointAlert = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var showingWaypointList = false
    
    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $position) {
                    if locationManager.userLocation != nil {
                        UserAnnotation()
                    }
                    
                    ForEach(waypointManager.waypoints) { waypoint in
                        Annotation(waypoint.name, coordinate: waypoint.coordinate) {
                            Button(action: {
                                selectedWaypoint = waypoint
                            }) {
                                Image(systemName: waypoint.iconName)
                                    .foregroundColor(.red)
                                    .font(.title2)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.red, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }
                .mapStyle(currentMapStyle)
                .onMapCameraChange { context in
                    // Handle camera changes if needed
                }
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        createWaypointAtTapLocation(coordinate)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                requestLocationPermission()
            }
            .onChange(of: locationManager.userLocation) { oldValue, newValue in
                if let location = newValue {
                    updateMapPosition(to: location)
                }
            }
            .alert("Send Waypoint to Helm?", isPresented: $showingWaypointAlert) {
                Button("Send") {
                    if let coordinate = pendingCoordinate {
                        sendWaypointToHelm(coordinate)
                        let waypoint = waypointManager.createWaypoint(at: coordinate)
                        logger.waypointCreated(waypoint.name, coordinate: String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                    }
                    pendingCoordinate = nil
                }
                Button("Cancel") {
                    pendingCoordinate = nil
                }
            } message: {
                if let coordinate = pendingCoordinate {
                    Text("Send waypoint at \(String(format: "%.6f", coordinate.latitude)), \(String(format: "%.6f", coordinate.longitude)) to Helm device for immediate navigation?")
                }
            }
            
            VStack {
                HStack {
                    // Enhanced status indicator with navigation data
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Circle()
                                .fill(bluetoothManager.isConnected ? .green : .red)
                                .frame(width: 12, height: 12)
                            
                            Text(bluetoothManager.isConnected ? "Helm Connected" : "Disconnected")
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            if bluetoothManager.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                        
                        // Enhanced: Show navigation enabled status in Map tab
                        if bluetoothManager.isConnected {
                            HStack {
                                Circle()
                                    .fill(isNavigationActive ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                
                                Text(navigationStatusText)
                                    .font(.caption2)
                                    .foregroundColor(isNavigationActive ? .green : .secondary)
                            }
                        }
                        
                        // Show navigation data when available
                        if let deviceStatus = bluetoothManager.deviceStatus,
                           let _ = deviceStatus.targetCoordinate {
                            Text("Distance: \(String(format: "%.0f", deviceStatus.distance))m")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
                    
                    Spacer()
                    
                    Button(action: toggleMapType) {
                        ZStack {
                            if isLoadingSatellite {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: mapType == .standard ? "map" : "globe")
                                    .foregroundColor(.primary)
                                    .font(.title2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                    }
                    .disabled(isLoadingSatellite)
                    .padding(.trailing)
                }
                .padding(.top, 60)
                
                Spacer()
                
                HStack {
                    Button(action: {
                        showingWaypointList = true
                    }) {
                        VStack {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.primary)
                                .font(.title2)
                            Text("\(waypointManager.waypoints.count)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .frame(width: 44, height: 50)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                    }
                    
                    Spacer()
                    
                    Button(action: centerOnUserLocation) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.primary)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing)
                }
                .padding(.bottom, 100)
            }
        }
        .sheet(item: $selectedWaypoint) { waypoint in
            WaypointDetailView(waypoint: waypoint, onSend: { coordinate in
                sendWaypointToHelm(coordinate)
            }, onDelete: { waypointToDelete in
                deleteWaypoint(waypointToDelete)
            })
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(waypoints: waypointManager.waypoints, onSend: { waypoint in
                sendWaypointToHelm(waypoint.coordinate)
            }, onDelete: { waypoint in
                deleteWaypoint(waypoint)
            }, onEdit: { waypoint in
                selectedWaypoint = waypoint
            })
        }
    }
    
    // MARK: - Navigation State Computed Properties
    
    private var isNavigationActive: Bool {
        guard let deviceStatus = bluetoothManager.deviceStatus else { return false }
        return deviceStatus.targetCoordinate != nil && deviceStatus.hasGpsFix
    }
    
    private var navigationStatusText: String {
        guard bluetoothManager.isConnected else { return "Not Connected" }
        
        if let deviceStatus = bluetoothManager.deviceStatus {
            if !deviceStatus.hasGpsFix {
                return "No GPS Fix"
            } else if deviceStatus.targetCoordinate == nil {
                return "No Waypoint"
            } else {
                return "Navigation Active"
            }
        }
        
        return "Status Unknown"
    }
    
    // MARK: - Map Functionality
    
    private var currentMapStyle: MapStyle {
        switch mapType {
        case .standard:
            return .standard
        case .satellite:
            return .imagery(elevation: .flat)
        default:
            return .standard
        }
    }
    
    private func requestLocationPermission() {
        locationManager.requestPermission()
    }
    
    private func updateMapPosition(to location: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 1.0)) {
            position = .region(MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
    
    private func toggleMapType() {
        if mapType == .standard {
            isLoadingSatellite = true
            mapType = .satellite
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isLoadingSatellite = false
            }
        } else {
            mapType = .standard
        }
    }
    
    private func centerOnUserLocation() {
        guard let location = locationManager.userLocation else { return }
        updateMapPosition(to: location)
    }
    
    private func createWaypointAtTapLocation(_ coordinate: CLLocationCoordinate2D) {
        if bluetoothManager.isConnected {
            pendingCoordinate = coordinate
            showingWaypointAlert = true
        } else {
            let _ = waypointManager.createWaypoint(at: coordinate)
        }
    }
    
    private func sendWaypointToHelm(_ coordinate: CLLocationCoordinate2D) {
        logger.startPerformanceMeasurement("waypoint_transmission", category: .bluetooth)
        bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        logger.endPerformanceMeasurement("waypoint_transmission", category: .bluetooth)
    }
    
    private func deleteWaypoint(_ waypoint: Waypoint) {
        waypointManager.deleteWaypoint(waypoint)
    }
}

#Preview {
    MapView()
        .environmentObject(BluetoothManager())
}