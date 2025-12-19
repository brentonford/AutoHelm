import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @Binding var selectedWaypoint: Waypoint?
    @Binding var waypoints: [Waypoint]
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingWaypointSheet = false
    @State private var showingWaypointList = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false
    
    var body: some View {
        ZStack {
            mapContent
            
            VStack {
                Spacer()
                if let waypoint = selectedWaypoint {
                    SelectedWaypointCard(waypoint: waypoint) {
                        deleteWaypoint(waypoint)
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingWaypointList = true
                } label: {
                    Label("Waypoints", systemImage: "list.bullet")
                }
            }
        }
        .sheet(isPresented: $showingWaypointSheet) {
            AddWaypointSheet(
                coordinate: pendingCoordinate,
                name: $waypointName,
                isLoading: isGeocodingName,
                onSave: addWaypoint,
                onCancel: {
                    showingWaypointSheet = false
                    waypointName = ""
                }
            )
            .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(waypoints: $waypoints, selectedWaypoint: $selectedWaypoint)
        }
    }
    
    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedWaypoint) {
                UserAnnotation()
                
                ForEach(waypoints) { waypoint in
                    Annotation(waypoint.name, coordinate: waypoint.coordinate) {
                        WaypointMarker(isSelected: selectedWaypoint?.id == waypoint.id)
                    }
                    .tag(waypoint)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { position in
                if let coordinate = proxy.convert(position, from: .local) {
                    pendingCoordinate = coordinate
                    getLocationName(for: coordinate)
                    showingWaypointSheet = true
                }
            }
        }
    }
    
    private func getLocationName(for coordinate: CLLocationCoordinate2D) {
        isGeocodingName = true
        waypointName = ""
        
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            isGeocodingName = false
            
            if let placemark = placemarks?.first {
                var components: [String] = []
                
                if let name = placemark.name {
                    components.append(name)
                } else if let thoroughfare = placemark.thoroughfare {
                    components.append(thoroughfare)
                }
                
                if let locality = placemark.locality {
                    components.append(locality)
                } else if let subLocality = placemark.subLocality {
                    components.append(subLocality)
                }
                
                if components.isEmpty {
                    if let administrativeArea = placemark.administrativeArea {
                        components.append(administrativeArea)
                    }
                }
                
                waypointName = components.isEmpty ? "Waypoint \(waypoints.count + 1)" : components.joined(separator: ", ")
            } else {
                waypointName = "Waypoint \(waypoints.count + 1)"
            }
        }
    }
    
    private func addWaypoint() {
        guard let coordinate = pendingCoordinate else { return }
        
        let name = waypointName.isEmpty ? "Waypoint \(waypoints.count + 1)" : waypointName
        let waypoint = Waypoint(coordinate: coordinate, name: name)
        waypoints.append(waypoint)
        selectedWaypoint = waypoint
        showingWaypointSheet = false
        waypointName = ""
    }
    
    private func deleteWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        if selectedWaypoint?.id == waypoint.id {
            selectedWaypoint = nil
        }
    }
}

// MARK: - Waypoint Marker

struct WaypointMarker: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.red)
                .frame(width: 30, height: 30)
            
            Image(systemName: "mappin")
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
        }
    }
}

// MARK: - Selected Waypoint Card

struct SelectedWaypointCard: View {
    let waypoint: Waypoint
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(waypoint.name)
                    .font(.headline)
                Text(String(format: "%.6f, %.6f",
                            waypoint.coordinate.latitude,
                            waypoint.coordinate.longitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Add Waypoint Sheet

struct AddWaypointSheet: View {
    let coordinate: CLLocationCoordinate2D?
    @Binding var name: String
    let isLoading: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                if let coord = coordinate {
                    Section("Location") {
                        Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Name") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Getting location name...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField("Waypoint name", text: $name)
                    }
                }
            }
            .navigationTitle("New Waypoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: onSave)
                        .disabled(isLoading)
                }
            }
        }
    }
}