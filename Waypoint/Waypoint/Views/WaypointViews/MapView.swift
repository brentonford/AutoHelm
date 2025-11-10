import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var mapType: MKMapType = .standard
    @State private var isLoadingSatellite: Bool = false
    @State private var waypoints: [Waypoint] = []
    @State private var selectedWaypoint: Waypoint?
    @State private var showingWaypointAlert = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    
    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $position) {
                    if locationManager.userLocation != nil {
                        UserAnnotation()
                    }
                    
                    ForEach(waypoints) { waypoint in
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
                loadWaypoints()
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
                        let waypoint = Waypoint(
                            coordinate: coordinate,
                            name: "Waypoint \(waypoints.count + 1)"
                        )
                        waypoints.append(waypoint)
                        saveWaypoints()
                    }
                    pendingCoordinate = nil
                }
                Button("Cancel") {
                    pendingCoordinate = nil
                }
            } message: {
                if let coordinate = pendingCoordinate {
                    Text("Send waypoint at \(String(format: "%.6f", coordinate.latitude)), \(String(format: "%.6f", coordinate.longitude)) to connected Helm device?")
                }
            }
            
            VStack {
                HStack {
                    // Bluetooth connection indicator
                    HStack {
                        Circle()
                            .fill(bluetoothManager.isConnected ? .green : .red)
                            .frame(width: 12, height: 12)
                        
                        Text(bluetoothManager.isConnected ? "Helm Connected" : "Helm Disconnected")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground).opacity(0.9))
                    .clipShape(Capsule())
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
    }
    
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
            let waypoint = Waypoint(
                coordinate: coordinate,
                name: "Waypoint \(waypoints.count + 1)"
            )
            waypoints.append(waypoint)
            saveWaypoints()
        }
    }
    
    private func sendWaypointToHelm(_ coordinate: CLLocationCoordinate2D) {
        bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    
    private func deleteWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        saveWaypoints()
    }
    
    private func saveWaypoints() {
        if let data = try? JSONEncoder().encode(waypoints) {
            UserDefaults.standard.set(data, forKey: "SavedWaypoints")
        }
    }
    
    private func loadWaypoints() {
        guard let data = UserDefaults.standard.data(forKey: "SavedWaypoints"),
              let savedWaypoints = try? JSONDecoder().decode([Waypoint].self, from: data) else {
            return
        }
        waypoints = savedWaypoints
    }
}

struct WaypointDetailView: View {
    let waypoint: Waypoint
    let onSend: (CLLocationCoordinate2D) -> Void
    let onDelete: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Waypoint Details")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name: \(waypoint.name)")
                    Text("Coordinates:")
                    Text("Lat: \(String(format: "%.6f", waypoint.coordinate.latitude))")
                    Text("Lon: \(String(format: "%.6f", waypoint.coordinate.longitude))")
                    Text("Created: \(waypoint.createdDate.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.body)
                
                HStack {
                    Button("Send to Helm") {
                        onSend(waypoint.coordinate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("Delete", role: .destructive) {
                        onDelete(waypoint)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    MapView()
}