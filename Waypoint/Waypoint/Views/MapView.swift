import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var bluetooth: BluetoothManager
    @Binding var selectedWaypoint: Waypoint?
    @Binding var waypoints: [Waypoint]
    @Binding var navigationEnabled: Bool

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingWaypointSheet = false
    @State private var showingWaypointList = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false

    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }

    var body: some View {
        ZStack {
            mapContent

            VStack {
                Spacer()
                if let waypoint = selectedWaypoint {
                    SelectedWaypointCard(
                        waypoint: waypoint,
                        isConfiguredInHelm: isWaypointConfiguredInHelm(waypoint),
                        onSendToHelm: {
                            sendWaypointToHelm(waypoint)
                        }
                    )
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    StatusIndicator(label: "Connection:", color: connectionColor)
                    StatusIndicator(label: "GPS:", color: gpsColor)
                    StatusIndicator(label: "Compass:", color: compassColor)
                    StatusIndicator(label: "Navigation:", color: navigationColor)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingWaypointList = true
                } label: {
                    Label("Waypoints", systemImage: "list.bullet")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if waypoints.isEmpty && selectedWaypoint == nil {
                Text("Long press on map to create a waypoint")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
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
            WaypointListView(waypoints: $waypoints, selectedWaypoint: $selectedWaypoint, navigationEnabled: $navigationEnabled)
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
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let location = drag?.location,
                               let coordinate = proxy.convert(location, from: .local) {
                                pendingCoordinate = coordinate
                                getLocationName(for: coordinate)
                                showingWaypointSheet = true
                            }
                        default:
                            break
                        }
                    }
            )
        }
    }

    // MARK: - Status Colors

    private var connectionColor: Color {
        switch bluetooth.connectionState {
        case .connected: return .green
        case .connecting, .scanning: return .orange
        case .disconnected: return .red
        }
    }

    private var gpsColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard let status = bluetooth.deviceStatus else { return .red }

        if !status.hasFix { return .red }
        if status.satellites < 4 || status.hdop >= 5.0 { return .orange }
        return .green
    }

    private var compassColor: Color {
        guard bluetooth.connectionState == .connected else { return .red }
        guard bluetooth.deviceStatus != nil else { return .red }
        return .green
    }

    private var navigationColor: Color {
        if !navigationEnabled { return .red }
        if navigationBlocked { return .orange }
        return .green
    }

    // MARK: - Geocoding

    private func isWaypointConfiguredInHelm(_ waypoint: Waypoint) -> Bool {
        guard let status = bluetooth.deviceStatus else { return false }
        guard let targetLat = status.targetLat, let targetLon = status.targetLon else { return false }

        let latMatch = abs(waypoint.coordinate.latitude - targetLat) < 0.000001
        let lonMatch = abs(waypoint.coordinate.longitude - targetLon) < 0.000001

        return latMatch && lonMatch
    }

    private func sendWaypointToHelm(_ waypoint: Waypoint) {
        guard bluetooth.connectionState == .connected else { return }
        bluetooth.sendWaypoint(waypoint)
        navigationEnabled = true
        bluetooth.enableNavigation()
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
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
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
    let isConfiguredInHelm: Bool
    let onSendToHelm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                if isConfiguredInHelm {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Button {
                onSendToHelm()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(isConfiguredInHelm ? "Resend to Helm" : "Send to Helm")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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