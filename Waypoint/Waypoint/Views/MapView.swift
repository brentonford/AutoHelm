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
    @State private var showingPreview = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false
    @State private var previewWaypoint: Waypoint?
    @State private var trackPoints: [TrackPoint] = []
    @State private var showDistanceRings = true
    @State private var showTrail = true
    @State private var lastTrackUpdate = Date()

    private let distanceRingRadii = [100.0, 500.0, 1000.0]
    private let trackUpdateInterval: TimeInterval = 5.0

    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }

    var body: some View {
        ZStack {
            mapContent

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button {
                            showDistanceRings.toggle()
                        } label: {
                            Image(systemName: showDistanceRings ? "circle.circle.fill" : "circle.circle")
                                .font(.title2)
                                .foregroundColor(Color.blue)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())

                        Button {
                            showTrail.toggle()
                        } label: {
                            Image(systemName: showTrail ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                                .font(.title2)
                                .foregroundColor(Color.blue)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())

                        if !trackPoints.isEmpty {
                            Button {
                                clearTrail()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(Color.red)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                        }
                    }
                    .padding()  
                }
                .padding(.top, 80)

                Spacer()

                if let waypoint = selectedWaypoint {
                    SelectedWaypointCard(
                        waypoint: waypoint,
                        isConfiguredInHelm: isWaypointConfiguredInHelm(waypoint),
                        navigationEnabled: navigationEnabled,
                        onPreview: {
                            showPreviewForWaypoint(waypoint)
                        },
                        onStopNavigation: {
                            stopNavigation()
                        }
                    )
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 16) {
                    SignalStrengthIndicator(
                        label: "BLE:",
                        signalStrength: bluetooth.signalStrength
                    )

                    if let status = bluetooth.deviceStatus {
                        GPSQualityIndicator(
                            label: "GPS:",
                            quality: status.gpsQuality
                        )
                    } else {
                        GPSQualityIndicator(
                            label: "GPS:",
                            quality: .noFix
                        )
                    }

                    StatusIndicator(
                        label: "Compass:", 
                        color: compassColor
                        )
                    StatusIndicator(
                        label: "Navigation:", 
                        color: navigationColor
                        )
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
        .sheet(isPresented: $showingPreview) {
            if let waypoint = previewWaypoint,
               let currentLocation = bluetooth.deviceStatus?.currentLocation {
                WaypointPreviewSheet(
                    preview: createPreview(for: waypoint, from: currentLocation),
                    onNavigate: {
                        showingPreview = false
                        navigateToWaypoint(waypoint)
                    },
                    onCancel: {
                        showingPreview = false
                        previewWaypoint = nil
                    }
                )
            }
        }
        .onChange(of: bluetooth.deviceStatus?.currentLocation) { _, newLocation in
            updateTrack(newLocation)
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

                if showDistanceRings, let currentLocation = bluetooth.deviceStatus?.currentLocation {
                    ForEach(distanceRingRadii, id: \.self) { radius in
                        MapCircle(center: currentLocation, radius: radius)
                            .foregroundStyle(Color.blue.opacity(0.1))
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    }
                }

                if showTrail && trackPoints.count > 1 {
                    MapPolyline(coordinates: trackPoints.map { $0.coordinate })
                        .stroke(Color.blue, lineWidth: 3)
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

    // MARK: - Track Management

    private func updateTrack(_ location: CLLocationCoordinate2D?) {
        guard let location = location else { return }
        guard Date().timeIntervalSince(lastTrackUpdate) >= trackUpdateInterval else { return }

        let point = TrackPoint(coordinate: location)
        trackPoints.append(point)

        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        trackPoints.removeAll { $0.timestamp < thirtyMinutesAgo }

        lastTrackUpdate = Date()
    }

    private func clearTrail() {
        trackPoints.removeAll()
    }

    // MARK: - Navigation Actions

    private func isWaypointConfiguredInHelm(_ waypoint: Waypoint) -> Bool {
        guard let status = bluetooth.deviceStatus else { return false }
        guard let targetLat = status.targetLat, let targetLon = status.targetLon else { return false }

        let latMatch = abs(waypoint.coordinate.latitude - targetLat) < 0.000001
        let lonMatch = abs(waypoint.coordinate.longitude - targetLon) < 0.000001

        return latMatch && lonMatch
    }

    private func showPreviewForWaypoint(_ waypoint: Waypoint) {
        previewWaypoint = waypoint
        showingPreview = true
    }

    private func navigateToWaypoint(_ waypoint: Waypoint) {
        guard bluetooth.connectionState == .connected else { return }
        selectedWaypoint = waypoint
        bluetooth.sendWaypoint(waypoint)
        navigationEnabled = true
        bluetooth.enableNavigation()
    }

    private func stopNavigation() {
        navigationEnabled = false
        bluetooth.disableNavigation()
    }

    private func createPreview(for waypoint: Waypoint, from currentLocation: CLLocationCoordinate2D) -> WaypointPreview {
        let distance = currentLocation.distance(to: waypoint.coordinate)
        let bearing = currentLocation.bearing(to: waypoint.coordinate)
        let averageSpeed = 1.0
        let estimatedTime = distance / averageSpeed

        return WaypointPreview(
            waypoint: waypoint,
            distance: distance,
            bearing: bearing,
            estimatedTime: estimatedTime
        )
    }

    // MARK: - Geocoding

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

// MARK: - Signal Strength Indicator

struct SignalStrengthIndicator: View {
    let label: String
    let signalStrength: BLESignalStrength

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            HStack(spacing: 2) {
                ForEach(1...4, id: \.self) { bar in
                    Rectangle()
                        .fill(bar <= signalStrength.bars ? Color(signalStrength.color) : Color.gray.opacity(0.3))
                        .frame(width: 3, height: CGFloat(bar) * 3)
                }
            }
        }
    }
}

// MARK: - GPS Quality Indicator

struct GPSQualityIndicator: View {
    let label: String
    let quality: GPSQuality

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Image(systemName: quality.icon)
                .font(.caption)
                .foregroundColor(Color(quality.color))
        }
    }
}

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
                .foregroundColor(Color.white)
                .font(.system(size: 16, weight: .bold))
        }
    }
}

// MARK: - Selected Waypoint Card

struct SelectedWaypointCard: View {
    let waypoint: Waypoint
    let isConfiguredInHelm: Bool
    let navigationEnabled: Bool
    let onPreview: () -> Void
    let onStopNavigation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            .foregroundColor(Color.green)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(Color.green)
                    }
                }
            }

            HStack(spacing: 12) {
                if navigationEnabled && isConfiguredInHelm {
                    Button {
                        onStopNavigation()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop Navigation")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.red)
                } else {
                    Button {
                        onPreview()
                    } label: {
                        Image(systemName: "info.circle")
                        Text("Preview")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Waypoint Preview Sheet

struct WaypointPreviewSheet: View {
    let preview: WaypointPreview
    let onNavigate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(preview.waypoint.name)
                        .font(.title2.bold())
                    Text(String(format: "%.6f, %.6f",
                                preview.waypoint.coordinate.latitude,
                                preview.waypoint.coordinate.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 40) {
                    VStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.title)
                            .foregroundColor(Color.blue)
                        Text(preview.distanceString)
                            .font(.title3.bold())
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        Image(systemName: "safari.fill")
                            .font(.title)
                            .foregroundColor(Color.green)
                        Text("\(preview.bearingString) \(preview.cardinalDirection)")
                            .font(.title3.bold())
                        Text("Bearing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text(preview.estimatedTimeString)
                            .font(.title3.bold())
                        Text("Est. Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                Text("Based on 3.6 km/hr (1 m/s) cruise speed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    onNavigate()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Navigate to Waypoint")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .font(.headline)
            }
            .padding()
            .navigationTitle("Waypoint Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
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
