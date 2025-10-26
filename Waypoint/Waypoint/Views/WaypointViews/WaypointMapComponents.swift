import SwiftUI
import CoreLocation
import MapKit

// MARK: - Map Reader Component
struct WaypointMapReader: View {
    @Binding var position: MapCameraPosition
    let mapStyle: MKMapType
    @ObservedObject var waypointManager: WaypointManager
    @ObservedObject var offlineTileManager: OfflineTileManager
    @ObservedObject var searchManager: SearchManager
    @ObservedObject var bluetoothManager: BluetoothManager
    let selectedWaypoint: Waypoint?
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onSearchResultTap: (MKMapItem, CLLocationCoordinate2D) -> Void
    
    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                mapAnnotations
            }
            .mapStyle(mapStyle == .standard ? .standard : .hybrid)
            .onTapGesture { screenCoordinate in
                if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                    onMapTap(coordinate)
                }
            }
        }
    }
    
    @MapContentBuilder
    private var mapAnnotations: some MapContent {
        UserAnnotation()
        savedWaypointsAnnotations
        activeTargetAnnotation
        searchResultsAnnotations
        selectedWaypointAnnotation
    }

    @MapContentBuilder
    private var savedWaypointsAnnotations: some MapContent {
        ForEach(waypointManager.savedWaypoints) { waypoint in
            Annotation("", coordinate: waypoint.coordinate) {
                SavedWaypointAnnotationView(waypoint: waypoint)
            }
        }
    }

    @MapContentBuilder
    private var activeTargetAnnotation: some MapContent {
        if let status = bluetoothManager.arduinoStatus, status.navigationActive {
            let targetCoordinate = CLLocationCoordinate2D(latitude: status.targetLat, longitude: status.targetLon)
            Annotation("", coordinate: targetCoordinate) {
                ActiveTargetAnnotationView()
            }
        }
    }

    @MapContentBuilder
    private var searchResultsAnnotations: some MapContent {
        ForEach(searchManager.searchResults, id: \.self) { item in
            if let coordinate = item.placemark.location?.coordinate {
                Annotation("", coordinate: coordinate) {
                    SearchResultAnnotationView(item: item)
                        .onTapGesture {
                            onSearchResultTap(item, coordinate)
                        }
                }
            }
        }
    }

    @MapContentBuilder
    private var selectedWaypointAnnotation: some MapContent {
        if let waypoint = selectedWaypoint, !waypoint.isSaved {
            Annotation("", coordinate: waypoint.coordinate) {
                SelectedWaypointAnnotationView()
            }
        }
    }
}

// MARK: - Map Overlay Component
struct WaypointMapOverlay: View {
    @ObservedObject var searchManager: SearchManager
    let showSearchResults: Bool
    let selectedWaypoint: Waypoint?
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    @Binding var showConfirmation: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var waypointToDelete: Waypoint?
    let isNavigationEnabled: Bool
    let onSelectWaypoint: (Waypoint?) -> Void
    let onSearchResultRowTap: (MKMapItem) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if showSearchResults && !searchManager.searchResults.isEmpty {
                SearchResultsList(
                    searchManager: searchManager,
                    onRowTap: onSearchResultRowTap
                )
            }
            
            Spacer()
            
            if let waypoint = selectedWaypoint {
                WaypointDetailCard(
                    waypoint: waypoint,
                    bluetoothManager: bluetoothManager,
                    waypointManager: waypointManager,
                    selectedWaypoint: .init(
                        get: { selectedWaypoint },
                        set: { onSelectWaypoint($0) }
                    ),
                    showConfirmation: $showConfirmation,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    waypointToDelete: $waypointToDelete,
                    isNavigationEnabled: isNavigationEnabled
                )
            } else {
                DefaultPromptView(
                    bluetoothManager: bluetoothManager,
                    isNavigationEnabled: isNavigationEnabled
                )
            }
        }
    }
}

// MARK: - Search Results List
struct SearchResultsList: View {
    @ObservedObject var searchManager: SearchManager
    let onRowTap: (MKMapItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(searchManager.searchResults.prefix(5)), id: \.self) { item in
                Button(action: {
                    onRowTap(item)
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown")
                                .foregroundColor(.primary)
                                .font(.subheadline)
                            if let address = item.placemark.title {
                                Text(address)
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                Divider()
            }
        }
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 2)
        .padding(.horizontal, 12)
    }
}

// MARK: - Default Prompt View
struct DefaultPromptView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let isNavigationEnabled: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if !bluetoothManager.isConnected {
                ConnectionStatusPrompt(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    text: "Connect to Helm device to send waypoints",
                    color: .orange
                )
            } else if !isNavigationEnabled {
                ConnectionStatusPrompt(
                    icon: "exclamationmark.triangle.fill",
                    text: "Navigation is disabled",
                    color: .orange
                )
            }
        }
    }
}

// MARK: - Connection Status Prompt
struct ConnectionStatusPrompt: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
                .foregroundColor(color)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Map Toolbar
struct WaypointMapToolbar: ToolbarContent {
    @ObservedObject var waypointManager: WaypointManager
    @Binding var searchText: String
    @Binding var showSearchResults: Bool
    @Binding var mapStyle: MKMapType
    @Binding var showSavedWaypoints: Bool
    let onSearch: () -> Void
    let onClearSearch: () -> Void
    let onCenterLocation: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 12) {
                WaypointCountButton(
                    count: waypointManager.savedWaypoints.count,
                    showSavedWaypoints: $showSavedWaypoints
                )
                
                MapStyleToggleButton(mapStyle: $mapStyle)
            }
        }
        
        ToolbarItem(placement: .principal) {
            SearchBar(
                searchText: $searchText,
                showSearchResults: $showSearchResults,
                onSearch: onSearch,
                onClear: onClearSearch
            )
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            LocationButton(onCenterLocation: onCenterLocation)
        }
    }
}

// MARK: - Toolbar Components
struct WaypointCountButton: View {
    let count: Int
    @Binding var showSavedWaypoints: Bool
    
    var body: some View {
        Button(action: {
            showSavedWaypoints.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text("\(count)")
            }
            .font(.caption)
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

struct MapStyleToggleButton: View {
    @Binding var mapStyle: MKMapType
    
    var body: some View {
        Button(action: {
            mapStyle = mapStyle == .standard ? .satellite : .standard
        }) {
            Image(systemName: mapStyle == .standard ? "map" : "globe.europe.africa")
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
        }
    }
}

struct SearchBar: View {
    @Binding var searchText: String
    @Binding var showSearchResults: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.caption)
            
            TextField("Search places...", text: $searchText, onEditingChanged: { isEditing in
                showSearchResults = isEditing && !searchText.isEmpty
            })
            .textFieldStyle(PlainTextFieldStyle())
            .font(.subheadline)
            .onSubmit(onSearch)
            
            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct LocationButton: View {
    let onCenterLocation: () -> Void
    
    var body: some View {
        Button(action: onCenterLocation) {
            Image(systemName: "location.fill")
                .font(.caption)
        }
    }
}