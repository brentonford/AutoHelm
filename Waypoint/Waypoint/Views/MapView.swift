import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @StateObject private var spotLockController: SpotLockController
    
    @Binding var selectedWaypoint: Waypoint?
    @Binding var waypoints: [Waypoint]
    @Binding var navigationEnabled: Bool

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingWaypointSheet = false
    @State private var showingWaypointList = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false
    @State private var showingArrivalAlert = false
    @State private var totalDistance: Double = 0
    @State private var spotLockTimer: Timer?
    
    init(selectedWaypoint: Binding<Waypoint?>, waypoints: Binding<[Waypoint]>, navigationEnabled: Binding<Bool>, bluetooth: BluetoothManager) {
        self._selectedWaypoint = selectedWaypoint
        self._waypoints = waypoints
        self._navigationEnabled = navigationEnabled
        self._spotLockController = StateObject(wrappedValue: SpotLockController(bluetooth: bluetooth))
    }
    
    private enum Constants {
        static let longPressMinimumDuration: Double = 0.5
    }

    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return sensors.hasFix && sensors.isNavigationReady
    }
    
    private var navigationFunctioning: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return navigationEnabled && sensors.isNavigationReady && selectedWaypoint != nil
    }
    
    private var isSpotLockActive: Bool {
        spotLockController.isActive
    }
    
    private var navigationProgress: Double {
        guard let sensors = bluetooth.sensorData,
              let waypoint = selectedWaypoint,
              totalDistance > 0 else { return 0 }
        
        let currentDistance = sensors.currentLocation.distance(to: waypoint.coordinate)
        let traveled = totalDistance - currentDistance
        return min(max(traveled / totalDistance, 0), 1.0)
    }

    var body: some View {
        ZStack {
            mapContent
            overlayControls
        }
        .toolbar {
            StatusToolbar(bluetooth: bluetooth) {
                showingWaypointList = true
            }
        }
        .overlay(alignment: .bottom) {
            if waypoints.isEmpty && selectedWaypoint == nil && !spotLockController.isActive {
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
        .onChange(of: selectedWaypoint?.id) { _, _ in
            handleWaypointChange()
        }
        .onChange(of: bluetooth.connectionState) { _, newState in
            if newState != .connected && navigationEnabled {
                navigationEnabled = false
            }
            if newState != .connected {
                totalDistance = 0
                Task {
                    await spotLockController.disengage()
                }
            }
        }
        .onChange(of: spotLockController.isActive) { _, isActive in
            if isActive {
                startSpotLockTimer()
            } else {
                stopSpotLockTimer()
            }
        }
        .onDisappear {
            stopSpotLockTimer()
        }
    }

    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedWaypoint) {
                if let sensors = bluetooth.sensorData {
                    let helmLocation = sensors.currentLocation
                    Annotation("Helm", coordinate: helmLocation) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 20, height: 20)
                        }
                    }
                }

                ForEach(waypoints) { waypoint in
                    Annotation(waypoint.name, coordinate: waypoint.coordinate) {
                        WaypointMarker(isSelected: selectedWaypoint?.id == waypoint.id)
                    }
                    .tag(waypoint)
                }
                
                if let sensors = bluetooth.sensorData,
                   let selected = selectedWaypoint {
                    let helmLocation = sensors.currentLocation
                    MapPolyline(coordinates: [helmLocation, selected.coordinate])
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
                
                if let lockPosition = spotLockController.lockPosition {
                    Annotation("Spot Lock", coordinate: lockPosition) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.3))
                                .frame(width: 40, height: 40)
                            Circle()
                                .stroke(Color.purple, lineWidth: 3)
                                .frame(width: 40, height: 40)
                            Image(systemName: "pin.fill")
                                .foregroundColor(.purple)
                                .font(.title2)
                        }
                    }
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
    
    private var overlayControls: some View {
        VStack {
            if spotLockController.isActive {
                spotLockStatusCard
                    .padding(.top)
            }

            Spacer()

            if let waypoint = selectedWaypoint {
                SelectedWaypointCard(
                    waypoint: waypoint,
                    isNavigationFunctioning: navigationFunctioning,
                    isSpotLockActive: isSpotLockActive,
                    navigationProgress: navigationProgress,
                    totalDistance: totalDistance,
                    sensorData: bluetooth.sensorData,
                    canNavigate: canNavigate,
                    onNavigate: {
                        navigateToWaypoint(waypoint)
                    },
                    onStopNavigation: {
                        stopNavigation()
                    },
                    onEngageSpotLock: {
                        toggleSpotLock()
                    },
                    onDisengageSpotLock: {
                        toggleSpotLock()
                    }
                )
                .padding()
            } else if !spotLockController.isActive {
                quickSpotLockButton
                    .padding()
            }
        }
    }
    
    private var spotLockStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pin.circle.fill")
                    .foregroundColor(.purple)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spot Lock Active")
                        .font(.headline)
                        .foregroundColor(.purple)
                    
                    if let lockPos = spotLockController.lockPosition {
                        Text(String(format: "%.6f, %.6f", lockPos.latitude, lockPos.longitude))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        await spotLockController.disengage()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                    Text(String(format: "%.2f m", spotLockController.distanceFromLock))
                        .font(.subheadline.bold())
                    Text("Distance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Image(systemName: spotLockController.isApplyingThrust ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title3)
                        .foregroundColor(spotLockController.isApplyingThrust ? .green : .orange)
                    Text(spotLockController.isApplyingThrust ? "Active" : "Holding")
                        .font(.subheadline.bold())
                    Text("Thrust")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if spotLockController.isApplyingThrust {
                    VStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.title3)
                            .foregroundColor(.purple)
                        Text("Level \(spotLockController.currentSpeedLevel)")
                            .font(.subheadline.bold())
                        Text("Speed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            jogControls
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var jogControls: some View {
        VStack(spacing: 8) {
            Text("Jog Position (1.5m)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button {
                    spotLockController.jog(direction: .left)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text("W")
                            .font(.caption2)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                
                VStack(spacing: 8) {
                    Button {
                        spotLockController.jog(direction: .forward)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text("N")
                                .font(.caption2)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        spotLockController.jog(direction: .back)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text("S")
                                .font(.caption2)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    spotLockController.jog(direction: .right)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                        Text("E")
                            .font(.caption2)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }
    
    private var quickSpotLockButton: some View {
        Button {
            toggleSpotLock()
        } label: {
            HStack {
                Image(systemName: "pin.circle.fill")
                Text("Engage Spot Lock Here")
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(!canNavigate)
    }
    
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
    
    private func handleWaypointChange() {
        guard let sensors = bluetooth.sensorData else { return }
        
        if let waypoint = selectedWaypoint {
            let helmLocation = sensors.currentLocation
            totalDistance = helmLocation.distance(to: waypoint.coordinate)
        }
    }
    
private func toggleSpotLock() {
    guard let sensors = bluetooth.sensorData else { return }
    
    Task {
        if spotLockController.isActive {
            await spotLockController.disengage()
        } else {
            let lockPosition = sensors.currentLocation
            await spotLockController.engage(at: lockPosition)
        }
    }
}
    
    private func startSpotLockTimer() {
        stopSpotLockTimer()
        spotLockTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await spotLockController.update()
            }
        }
    }
    
    private func stopSpotLockTimer() {
        spotLockTimer?.invalidate()
        spotLockTimer = nil
    }

    private func navigateToWaypoint(_ waypoint: Waypoint) {
        guard bluetooth.connectionState == .connected else { return }
        guard let sensors = bluetooth.sensorData else { return }
        
        let helmLocation = sensors.currentLocation
        selectedWaypoint = waypoint
        totalDistance = helmLocation.distance(to: waypoint.coordinate)
        navigationEnabled = true
    }

    private func stopNavigation() {
        navigationEnabled = false
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
        
        DataStore.shared.saveWaypoints()
    }
}