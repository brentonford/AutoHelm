import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var bluetooth: BluetoothManager
    
    @Binding var selectedWaypoint: Waypoint?
    @Binding var waypoints: [Waypoint]
    @Binding var navigationEnabled: Bool

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingWaypointSheet = false
    @State private var showingWaypointList = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false
    @State private var trackPoints: [TrackPoint] = []
    @State private var showDistanceRings = true
    @State private var showTrail = true
    @State private var lastTrackUpdate = Date()
    @State private var showingArrivalAlert = false
    @State private var totalDistance: Double = 0
    @State private var lastSteeringCommand: String = "None"
    @State private var lastSpeedCommand: String = "None"
    @State private var lastCommandTime: Date?
    
    // MARK: - Constants
    
    private enum Constants {
        static let distanceRingRadii: [Double] = [100.0, 500.0, 1000.0]
        static let trackUpdateIntervalSeconds: TimeInterval = 5.0
        static let headingToleranceDegrees: Double = 15.0
        static let trackRetentionMinutes: TimeInterval = 30 * 60
        static let longPressMinimumDuration: Double = 0.5
        static let trailClearLongPressDuration: Double = 3.0
    }

    // MARK: - Computed Properties
    
    private var navigationBlocked: Bool {
        guard bluetooth.connectionState == .connected else { return true }
        guard let status = bluetooth.deviceStatus else { return true }
        return !status.isNavigationReady
    }
    
    private var isActiveNavigation: Bool {
        guard let status = bluetooth.deviceStatus else { return false }
        return navigationEnabled && status.hasTarget == true
    }
    
    private var navigationProgress: Double {
        guard let status = bluetooth.deviceStatus,
              status.hasTarget == true,
              totalDistance > 0 else { return 0 }
        
        let remaining = status.distance
        let traveled = totalDistance - remaining
        return min(max(traveled / totalDistance, 0), 1.0)
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

    // MARK: - Body
    
    var body: some View {
        ZStack {
            mapContent
            overlayControls
        }
        .toolbar {
            toolbarContent
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
            .presentationDetents([.height(400)])
        }
        .sheet(isPresented: $showingWaypointList) {
            WaypointListView(
                waypoints: $waypoints,
                selectedWaypoint: $selectedWaypoint,
                navigationEnabled: $navigationEnabled
            )
        }
        .alert("Arrived!", isPresented: $showingArrivalAlert) {
            Button("OK") {
                showingArrivalAlert = false
            }
        } message: {
            if let waypoint = selectedWaypoint {
                Text("You have arrived at \(waypoint.name)")
            }
        }
        .onChange(of: bluetooth.deviceStatus?.currentLocation) { _, newLocation in
            updateTrack(newLocation)
        }
        .onChange(of: bluetooth.deviceStatus?.distance) { oldValue, newValue in
            checkArrival(oldDistance: oldValue, newDistance: newValue)
        }
        .onChange(of: navigationEnabled) { _, enabled in
            handleNavigationToggle(enabled)
        }
        .onChange(of: selectedWaypoint?.id) { _, _ in
            handleWaypointChange()
        }
        .onChange(of: bluetooth.deviceStatus?.relative) { _, newValue in
            updateSteeringCommand(relative: newValue)
        }
        .onChange(of: bluetooth.deviceStatus?.speedLevel) { oldValue, newValue in
            updateSpeedCommand(oldLevel: oldValue, newLevel: newValue)
        }
    }

    // MARK: - Map Content
    
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
                    ForEach(Constants.distanceRingRadii, id: \.self) { radius in
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
                LongPressGesture(minimumDuration: Constants.longPressMinimumDuration)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        handleMapLongPress(value: value, proxy: proxy)
                    }
            )
        }
    }
    
    // MARK: - Overlay Controls
    
    private var overlayControls: some View {
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
                    .accessibilityLabel("Toggle distance rings")

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
                    .accessibilityLabel("Toggle trail")
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: Constants.trailClearLongPressDuration)
                            .onEnded { _ in
                                clearTrail()
                            }
                    )
                }
                .padding()
            }
            .padding(.top, 80)

            Spacer()

            if let waypoint = selectedWaypoint {
                SelectedWaypointCard(
                    waypoint: waypoint,
                    isActiveNavigation: isActiveNavigation,
                    navigationProgress: navigationProgress,
                    totalDistance: totalDistance,
                    currentLocation: bluetooth.deviceStatus?.currentLocation,
                    deviceStatus: bluetooth.deviceStatus,
                    lastSteeringCommand: lastSteeringCommand,
                    lastSpeedCommand: lastSpeedCommand,
                    lastCommandTime: lastCommandTime,
                    onNavigate: {
                        navigateToWaypoint(waypoint)
                    },
                    onStopNavigation: {
                        stopNavigation()
                    }
                )
                .padding()
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - Event Handlers
    
    private func handleMapLongPress(value: SequenceGesture<LongPressGesture, DragGesture>.Value, proxy: MapProxy) {
        switch value {
        case .second(true, let drag):
            guard let location = drag?.location,
                  let coordinate = proxy.convert(location, from: .local) else { return }
            pendingCoordinate = coordinate
            getLocationName(for: coordinate)
            showingWaypointSheet = true
        default:
            break
        }
    }
    
    private func handleNavigationToggle(_ enabled: Bool) {
        guard enabled, let status = bluetooth.deviceStatus, status.hasTarget == true else { return }
        totalDistance = status.distance
    }
    
    private func handleWaypointChange() {
        guard navigationEnabled, let status = bluetooth.deviceStatus, status.hasTarget == true else { return }
        totalDistance = status.distance
    }

    private func updateTrack(_ location: CLLocationCoordinate2D?) {
        guard let location else { return }
        guard Date().timeIntervalSince(lastTrackUpdate) >= Constants.trackUpdateIntervalSeconds else { return }

        let point = TrackPoint(coordinate: location)
        trackPoints.append(point)

        let cutoffTime = Date().addingTimeInterval(-Constants.trackRetentionMinutes)
        trackPoints.removeAll { $0.timestamp < cutoffTime }

        lastTrackUpdate = Date()
    }

    private func clearTrail() {
        trackPoints.removeAll()
    }
    
    private func checkArrival(oldDistance: Double?, newDistance: Double?) {
        guard let newDistance,
              let waypoint = selectedWaypoint,
              navigationEnabled else { return }
        
        guard newDistance <= waypoint.arrivalRadius else { return }
        
        showingArrivalAlert = true
        navigationEnabled = false
        bluetooth.disableNavigation()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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

    private func getLocationName(for coordinate: CLLocationCoordinate2D) {
        isGeocodingName = true
        waypointName = ""

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            isGeocodingName = false

            guard let placemark = placemarks?.first else {
                waypointName = "Waypoint \(waypoints.count + 1)"
                return
            }
            
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

            if components.isEmpty, let administrativeArea = placemark.administrativeArea {
                components.append(administrativeArea)
            }

            waypointName = components.isEmpty ? "Waypoint \(waypoints.count + 1)" : components.joined(separator: ", ")
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
    
    private func updateSteeringCommand(relative: Double?) {
        guard navigationEnabled, let relative else {
            lastSteeringCommand = "None"
            lastCommandTime = nil
            return
        }
        
        let absAngle = abs(relative)
        
        if absAngle <= Constants.headingToleranceDegrees {
            lastSteeringCommand = "On Course"
        } else if relative > 0 {
            lastSteeringCommand = "RIGHT"
        } else {
            lastSteeringCommand = "LEFT"
        }
        lastCommandTime = Date()
    }
    
    private func updateSpeedCommand(oldLevel: Int?, newLevel: Int?) {
        guard navigationEnabled else {
            lastSpeedCommand = "None"
            return
        }
        
        guard let oldLevel, let newLevel else { return }
        
        if newLevel > oldLevel {
            lastSpeedCommand = "SPEED +"
            lastCommandTime = Date()
        } else if newLevel < oldLevel {
            lastSpeedCommand = "SPEED -"
            lastCommandTime = Date()
        }
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
                .foregroundColor(Color.white)
                .font(.system(size: 16, weight: .bold))
        }
        .accessibilityLabel(isSelected ? "Selected waypoint" : "Waypoint")
    }
}

// MARK: - Selected Waypoint Card

struct SelectedWaypointCard: View {
    let waypoint: Waypoint
    let isActiveNavigation: Bool
    let navigationProgress: Double
    let totalDistance: Double
    let currentLocation: CLLocationCoordinate2D?
    let deviceStatus: DeviceStatus?
    let lastSteeringCommand: String
    let lastSpeedCommand: String
    let lastCommandTime: Date?
    let onNavigate: () -> Void
    let onStopNavigation: () -> Void
    
    // MARK: - Computed Properties
    
    private var distance: Double? {
        guard let currentLocation else { return nil }
        return currentLocation.distance(to: waypoint.coordinate)
    }
    
    private var bearing: Double? {
        guard let currentLocation else { return nil }
        return currentLocation.bearing(to: waypoint.coordinate)
    }
    
    private var estimatedTime: TimeInterval? {
        guard let distance else { return nil }
        let averageSpeed = 1.0
        return distance / averageSpeed
    }

    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            
            if isActiveNavigation {
                activeNavigationContent
            } else {
                inactiveNavigationContent
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Header
    
    private var headerRow: some View {
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

            if isActiveNavigation {
                HStack(spacing: 4) {
                    if let estimatedTime {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.title3)
                                .foregroundColor(Color.green)
                            Text(formatEstimatedTime(estimatedTime))
                                .font(.subheadline.bold())
                            Text("Est. Time")
                                .font(.caption)
                                .foregroundColor(Color.green)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Active Navigation Content
    
    private var activeNavigationContent: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Progress")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(navigationProgress * 100))%")
                    .font(.subheadline.bold())
            }
            
            ProgressView(value: navigationProgress, total: 1.0)
                .tint(Color.blue)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let status = deviceStatus {
                        Text(formatDistance(status.distance))
                            .font(.headline)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDistance(totalDistance))
                        .font(.headline)
                }
            }
            
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
        }
    }
    
    // MARK: - Inactive Navigation Content
    
    private var inactiveNavigationContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 40) {
                if let distance {
                    VStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.title3)
                            .foregroundColor(Color.blue)
                        Text(formatDistance(distance))
                            .font(.subheadline.bold())
                        Text("Distance")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let bearing {
                    VStack(spacing: 4) {
                        Image(systemName: "safari.fill")
                            .font(.title3)
                            .foregroundColor(Color.green)
                        Text("\(Int(bearing)) deg \(cardinalDirection(for: bearing))")
                            .font(.subheadline.bold())
                        Text("Bearing")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let estimatedTime {
                    VStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text(formatEstimatedTime(estimatedTime))
                            .font(.subheadline.bold())
                        Text("Est. Time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            
            Button {
                onNavigate()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Navigate to Waypoint")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
    
    private func formatEstimatedTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5) / 45.0) % 8
        return directions[index]
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