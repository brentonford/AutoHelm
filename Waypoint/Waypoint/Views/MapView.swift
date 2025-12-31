import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var spotLockController: SpotLockController
    
    @Binding var selectedWaypoint: Waypoint?
    @Binding var waypoints: [Waypoint]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingWaypointSheet = false
    @State private var showingWaypointList = false
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var waypointName = ""
    @State private var isGeocodingName = false
    
    private enum Constants {
        static let longPressMinimumDuration: Double = 0.5
    }

    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return sensors.hasFix && sensors.isNavigationReady
    }
    
    private var isSpotLockActive: Bool {
        spotLockController.isActive
    }

    private var bearing: Double? {
        guard let sensors = bluetooth.sensorData,
        let lockPos = spotLockController.lockPosition else { return nil }
        let currentLocation = sensors.currentLocation
        return currentLocation.bearing(to: lockPos)
    }

    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((bearing + 11.25) / 22.5) % 16
        return directions[index]
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
        // .overlay(alignment: .bottom) {
        //     if waypoints.isEmpty && selectedWaypoint == nil && !spotLockController.isActive {
        //         Text("Long press on map to create a waypoint")
        //             .font(.caption)
        //             .padding(8)
        //             .background(.ultraThinMaterial)
        //             .cornerRadius(8)
        //             .padding(.bottom, 16)
        //     }
        // }
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
                selectedWaypoint: $selectedWaypoint
            )
        }
    }

    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedWaypoint) {
                if let sensors = bluetooth.sensorData {
                    let helmLocation = sensors.currentLocation
                    Annotation("Helm", coordinate: helmLocation) {
                        ZStack {
                            // Background circle
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 30, height: 30)
                            
                            // White border
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 30, height: 30)
                            
                            // Arrow pointing in heading direction
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(sensors.heading))
                        }
                    }
                }

                ForEach(waypoints) { waypoint in
                    Annotation(waypoint.name, coordinate: waypoint.coordinate) {
                        WaypointMarker(isSelected: selectedWaypoint?.id == waypoint.id)
                    }
                    .tag(waypoint)
                }
                
                if let lockPosition = spotLockController.lockPosition {
                    Annotation("Spot Lock", coordinate: lockPosition) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 40, height: 40)
                            Circle()
                                .stroke(Color.blue, lineWidth: 3)
                                .frame(width: 40, height: 40)
                            Image(systemName: "pin.fill")
                                .foregroundColor(.blue)
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
            Spacer()

            if spotLockController.isActive {
                spotLockStatusCard
                    .padding()
            } else if let waypoint = selectedWaypoint {
                SelectedWaypointCard(
                    waypoint: waypoint,
                    isSpotLockActive: isSpotLockActive,
                    sensorData: bluetooth.sensorData,
                    canNavigate: canNavigate,
                    onEngageSpotLock: {
                        Task {
                            await spotLockController.engage(at: waypoint.coordinate)
                        }
                    },
                    onDisengageSpotLock: {
                        Task {
                            await spotLockController.disengage()
                        }
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
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spot Lock Active")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
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
                
                if let bearing {
                    VStack(spacing: 4) {
                        Image(systemName: "safari.fill")
                            .font(.title3)
                            .foregroundColor(Color.green)
                        Text("\(Int(bearing))° \(cardinalDirection(for: bearing))")
                            .font(.subheadline.bold())
                        Text("Bearing")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.title3)
                        .foregroundColor(spotLockController.isApplyingThrust ? .green : .orange)
                    Text("Level \(spotLockController.currentSpeedLevel)")
                        .font(.subheadline.bold())
                    Text("Speed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
        HStack() {
            Spacer()

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
        .padding()

            Spacer()
        }
    }
    
    private var quickSpotLockButton: some View {
        Button {
            Task {
                guard let sensors = bluetooth.sensorData else { return }
                await spotLockController.engage(at: sensors.currentLocation)
            }
        } label: {
            HStack {
                Image(systemName: "pin.circle.fill")
                Text("Engage Spot Lock Here")
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
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