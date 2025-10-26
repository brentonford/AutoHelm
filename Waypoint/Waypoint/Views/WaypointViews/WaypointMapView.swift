import SwiftUI
import CoreLocation
import MapKit

struct WaypointMapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @StateObject private var searchManager = SearchManager()
    
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedWaypoint: Waypoint?
    @State private var showConfirmation = false
    @State private var showSavedWaypoints = false
    @State private var editingWaypointId: UUID?
    @State private var editingWaypointName: String = ""
    @State private var hasSetInitialPosition = false
    @State private var searchText = ""
    @State private var showSearchResults = false
    @State private var mapStyle: MKMapType = .satellite
    @State private var showMapStylePicker = false
    @State private var showDeleteConfirmation = false
    @State private var waypointToDelete: Waypoint?
    @State private var isNavigationEnabled = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                WaypointMapReader(
                    position: $position,
                    mapStyle: mapStyle,
                    waypointManager: waypointManager,
                    offlineTileManager: offlineTileManager,
                    searchManager: searchManager,
                    bluetoothManager: bluetoothManager,
                    selectedWaypoint: selectedWaypoint,
                    onMapTap: handleMapTap,
                    onSearchResultTap: handleSearchResultTap
                )
                .ignoresSafeArea()
                
                WaypointMapOverlay(
                    searchManager: searchManager,
                    showSearchResults: showSearchResults,
                    selectedWaypoint: selectedWaypoint,
                    bluetoothManager: bluetoothManager,
                    waypointManager: waypointManager,
                    showConfirmation: $showConfirmation,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    waypointToDelete: $waypointToDelete,
                    isNavigationEnabled: isNavigationEnabled,
                    onSelectWaypoint: { selectedWaypoint = $0 },
                    onSearchResultRowTap: handleSearchResultRowTap
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WaypointMapToolbar(
                    waypointManager: waypointManager,
                    searchText: $searchText,
                    showSearchResults: $showSearchResults,
                    mapStyle: $mapStyle,
                    showSavedWaypoints: $showSavedWaypoints,
                    onSearch: handleSearchSubmit,
                    onClearSearch: clearSearch,
                    onCenterLocation: centerOnUserLocation
                )
            }
        }
        .onChange(of: locationManager.location) { oldValue, newLocation in
            handleLocationChange(newLocation)
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(newValue)
        }
        .onChange(of: bluetoothManager.arduinoStatus) { oldValue, newValue in
            if let status = newValue {
                isNavigationEnabled = status.navigationActive
            }
        }
    }
    
    // MARK: - Action Methods
    
    private func handleMapTap(coordinate: CLLocationCoordinate2D) {
        waypointManager.fetchLocationName(for: coordinate) { locationName in
            let waypoint = Waypoint(coordinate: coordinate, name: locationName)
            selectedWaypoint = waypoint
        }
    }
    
    private func handleSearchResultTap(_ item: MKMapItem, coordinate: CLLocationCoordinate2D) {
        let waypoint = Waypoint(coordinate: coordinate, name: item.name ?? "Search Result")
        selectedWaypoint = waypoint
        clearSearch()
    }
    
    private func handleSearchResultRowTap(_ item: MKMapItem) {
        if let coordinate = item.placemark.location?.coordinate {
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            let region = MKCoordinateRegion(center: coordinate, span: span)
            position = .region(region)
            let waypoint = Waypoint(coordinate: coordinate, name: item.name ?? "Search Result")
            selectedWaypoint = waypoint
            clearSearch()
        }
    }
    
    private func handleLocationChange(_ newLocation: CLLocation?) {
        if let location = newLocation, !hasSetInitialPosition {
            let coordinateSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            let coordinateRegion = MKCoordinateRegion(center: location.coordinate, span: coordinateSpan)
            position = .region(coordinateRegion)
            hasSetInitialPosition = true
        }
    }
    
    private func handleSearchTextChange(_ newValue: String) {
        if newValue.isEmpty {
            searchManager.clearSearch()
            showSearchResults = false
        } else if newValue.count > 2 {
            let mapRegion = getCurrentMapRegion()
            if let region = mapRegion {
                searchManager.searchForPlaces(query: newValue, region: region)
                showSearchResults = true
            }
        }
    }
    
    private func handleSearchSubmit() {
        if let region = getCurrentMapRegion() {
            searchManager.searchForPlaces(query: searchText, region: region)
            showSearchResults = true
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchManager.clearSearch()
        showSearchResults = false
    }
    
    private func centerOnUserLocation() {
        if let location = locationManager.location {
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            let region = MKCoordinateRegion(center: location.coordinate, span: span)
            position = .region(region)
        }
    }
    
    private func getCurrentMapRegion() -> MKCoordinateRegion? {
        if let location = locationManager.location {
            return MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return nil
    }
}