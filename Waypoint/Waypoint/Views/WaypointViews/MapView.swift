import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var waypointManager = WaypointManager()
    @EnvironmentObject var bluetoothManager: BluetoothManager
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
                        let _ = waypointManager.createWaypoint(at: coordinate)
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
                    // Bluetooth connection indicator
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
        bluetoothManager.sendWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    
    private func deleteWaypoint(_ waypoint: Waypoint) {
        waypointManager.deleteWaypoint(waypoint)
    }
    

}

struct WaypointListView: View {
    let waypoints: [Waypoint]
    let onSend: (Waypoint) -> Void
    let onDelete: (Waypoint) -> Void
    let onEdit: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        NavigationView {
            List {
                ForEach(waypoints) { waypoint in
                    WaypointRowView(waypoint: waypoint, onSend: onSend, onEdit: onEdit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(waypoint)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                onEdit(waypoint)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        onDelete(waypoints[index])
                    }
                }
            }
            .navigationTitle("Waypoints (\(waypoints.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WaypointRowView: View {
    let waypoint: Waypoint
    let onSend: (Waypoint) -> Void
    let onEdit: (Waypoint) -> Void
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: waypoint.iconName)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text(waypoint.name)
                            .font(.headline)
                    }
                    
                    Text("\(String(format: "%.6f", waypoint.coordinate.latitude)), \(String(format: "%.6f", waypoint.coordinate.longitude))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !waypoint.comments.isEmpty {
                        Text(waypoint.comments)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    print("Sending waypoint: \(waypoint.name)")
                    onSend(waypoint)
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!bluetoothManager.isConnected)
            }
            
            if !bluetoothManager.isConnected {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Helm device not connected")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct WaypointDetailView: View {
    let waypoint: Waypoint
    let onSend: (CLLocationCoordinate2D) -> Void
    let onDelete: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
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
                    .disabled(!bluetoothManager.isConnected)
                    
                    Spacer()
                    
                    Button("Delete", role: .destructive) {
                        onDelete(waypoint)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                
                if !bluetoothManager.isConnected {
                    Text("Connect to Helm device to send waypoints")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top)
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
        .environmentObject(BluetoothManager())
}