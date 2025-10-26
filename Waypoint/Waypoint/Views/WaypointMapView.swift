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
                Map(position: $position) {
                    UserAnnotation()
                    
                    ForEach(waypointManager.savedWaypoints) { waypoint in
                        Annotation("", coordinate: waypoint.coordinate) {
                            savedWaypointAnnotationView(waypoint)
                                .onTapGesture {
                                    selectedWaypoint = waypoint
                                }
                        }
                    }
                    
                    ForEach(searchManager.searchResults, id: \.self) { item in
                        if let coordinate = item.placemark.location?.coordinate {
                            Annotation("", coordinate: coordinate) {
                                searchResultAnnotationView(item)
                                    .onTapGesture {
                                        handleSearchResultTap(item, coordinate: coordinate)
                                    }
                            }
                        }
                    }
                    
                    if let waypoint = selectedWaypoint, !waypoint.isSaved {
                        Annotation("", coordinate: waypoint.coordinate) {
                            selectedWaypointAnnotationView()
                        }
                    }
                    
                    // Downloaded regions hidden from waypoint view
                }
                .mapStyle(mapStyle == .standard ? .standard : .hybrid)
                .onTapGesture { screenCoordinate in
                    handleMapTap(screenCoordinate: screenCoordinate)
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if showSearchResults && !searchManager.searchResults.isEmpty {
                        searchResultsListView
                    }
                    
                    Spacer()
                    
                    // Navigation toggle removed - controlled by Send to Arduino button
                    
                    if let waypoint = selectedWaypoint {
                        WaypointDetailCard(
                            waypoint: waypoint,
                            bluetoothManager: bluetoothManager,
                            waypointManager: waypointManager,
                            selectedWaypoint: $selectedWaypoint,
                            showConfirmation: $showConfirmation,
                            showDeleteConfirmation: $showDeleteConfirmation,
                            waypointToDelete: $waypointToDelete,
                            isNavigationEnabled: isNavigationEnabled
                        )
                    } else {
                        defaultPromptView
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .onChange(of: locationManager.location) { oldValue, newLocation in
            handleLocationChange(newLocation)
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(newValue)
        }
    }
    
    // MARK: - Annotation Views
    
    private func savedWaypointAnnotationView(_ waypoint: Waypoint) -> some View {
        VStack(spacing: 0) {
            Image(systemName: waypoint.iconName)
                .font(.system(size: 16))
                .foregroundColor(.yellow)
                .background(Color.white)
                .clipShape(Circle())
            Text(waypoint.name)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.8))
                .cornerRadius(4)
        }
    }
    
    private func searchResultAnnotationView(_ item: MKMapItem) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .background(Color.white)
                .clipShape(Circle())
            Text(item.name ?? "")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(4)
        }
    }
    
    private func selectedWaypointAnnotationView() -> some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 20))
                .foregroundColor(.red)
                .offset(y: -10)
        }
    }
    
    private func offlineRegionAnnotationView(_ region: DownloadedRegion) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
                .background(Color.white)
                .clipShape(Circle())
            Text(region.name)
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green)
                .cornerRadius(4)
        }
    }
    
    // MARK: - UI Components
    
    private var searchResultsListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(searchManager.searchResults.prefix(5)), id: \.self) { item in
                Button(action: {
                    handleSearchResultRowTap(item)
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
    
    // Navigation toggle removed - controlled by Send to Arduino button
    
    private var defaultPromptView: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .foregroundColor(.blue)
            Text("Tap anywhere on the map to set a waypoint")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 12) {
                Button(action: {
                    showSavedWaypoints.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("\(waypointManager.savedWaypoints.count)")
                    }
                    .font(.caption)
                }
                
                Button(action: {
                    showMapStylePicker.toggle()
                }) {
                    Image(systemName: mapStyle == .standard ? "map" : "globe.europe.africa")
                        .font(.caption)
                }
            }
        }
        
        ToolbarItem(placement: .principal) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.caption)
                
                TextField("Search places...", text: $searchText, onEditingChanged: { isEditing in
                    showSearchResults = isEditing && !searchText.isEmpty
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.subheadline)
                .onSubmit {
                    handleSearchSubmit()
                }
                
                if !searchText.isEmpty {
                    Button(action: {
                        clearSearch()
                    }) {
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
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                centerOnUserLocation()
            }) {
                Image(systemName: "location.fill")
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Action Methods
    
    private func handleMapTap(screenCoordinate: CGPoint) {
        let coordinate = convertScreenToCoordinate(screenCoordinate)
        waypointManager.fetchLocationName(for: coordinate) { locationName in
            let waypoint = Waypoint(coordinate: coordinate, name: locationName)
            selectedWaypoint = waypoint
        }
    }
    
    private func convertScreenToCoordinate(_ screenCoordinate: CGPoint) -> CLLocationCoordinate2D {
        if let currentLocation = locationManager.location {
            let lat = currentLocation.coordinate.latitude + Double(screenCoordinate.y - 200) * 0.0001
            let lon = currentLocation.coordinate.longitude + Double(screenCoordinate.x - 200) * 0.0001
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return CLLocationCoordinate2D(latitude: -32.940931, longitude: 151.718029)
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

struct WaypointDetailCard: View {
    let waypoint: Waypoint
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    @Binding var selectedWaypoint: Waypoint?
    @Binding var showConfirmation: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var waypointToDelete: Waypoint?
    let isNavigationEnabled: Bool
    @State private var showEditSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if waypoint.isSaved {
                        HStack {
                            Image(systemName: waypoint.iconName)
                                .foregroundColor(.blue)
                            Text(waypoint.name)
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                    } else {
                        Text("Selected Waypoint")
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    Text("Lat: \(waypoint.coordinate.latitude, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                    Text("Lon: \(waypoint.coordinate.longitude, specifier: "%.6f")")
                        .font(.system(.caption, design: .monospaced))
                    
                    if waypoint.isSaved {
                        Text("Created: \(waypoint.createdDate, style: .date)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        if waypoint.lastUpdatedDate != waypoint.createdDate {
                            Text("Updated: \(waypoint.lastUpdatedDate, style: .date)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: {
                    selectedWaypoint = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            
            if !isNavigationEnabled {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Navigation is disabled")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            if waypoint.isSaved {
                savedWaypointButtons
            } else {
                newWaypointButtons
            }
            
            if !bluetoothManager.isConnected && !waypoint.isSaved {
                Text("Connect to Arduino to send waypoint")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .italic()
            }
            
            if showConfirmation {
                confirmationView
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showEditSheet) {
            EditWaypointView(waypoint: waypoint, waypointManager: waypointManager, selectedWaypoint: $selectedWaypoint)
        }
    }
    
    private var savedWaypointButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                showEditSheet = true
            }) {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            
            if bluetoothManager.isConnected {
                Button(action: {
                    sendWaypointAction()
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            Button(action: {
                waypointToDelete = waypoint
                showDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    private var newWaypointButtons: some View {
        VStack(spacing: 8) {
            if bluetoothManager.isConnected {
                Button(action: {
                    sendWaypointAction()
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send to Arduino")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            Button(action: {
                waypointManager.saveWaypoint(waypoint)
                selectedWaypoint = waypointManager.savedWaypoints.last
            }) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Save Waypoint")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    private var confirmationView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Waypoint sent!")
                .font(.subheadline)
        }
        .padding(6)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func sendWaypointAction() {
        bluetoothManager.sendWaypoint(
            latitude: waypoint.coordinate.latitude,
            longitude: waypoint.coordinate.longitude
        )
        // Enable navigation when sending waypoint to Arduino
        bluetoothManager.setNavigationEnabled(true)
        showConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showConfirmation = false
        }
    }
}

struct EditWaypointView: View {
    let waypoint: Waypoint
    @ObservedObject var waypointManager: WaypointManager
    @Binding var selectedWaypoint: Waypoint?
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var comments: String
    @State private var selectedIcon: String
    
    let iconOptions = [
        "mappin.circle.fill",
        "star.circle.fill", 
        "flag.circle.fill",
        "heart.circle.fill",
        "house.circle.fill",
        "car.circle.fill",
        "boat.circle.fill",
        "airplane.circle.fill"
    ]
    
    init(waypoint: Waypoint, waypointManager: WaypointManager, selectedWaypoint: Binding<Waypoint?>) {
        self.waypoint = waypoint
        self.waypointManager = waypointManager
        self._selectedWaypoint = selectedWaypoint
        self._name = State(initialValue: waypoint.name)
        self._comments = State(initialValue: waypoint.comments)
        self._selectedIcon = State(initialValue: waypoint.iconName)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                    TextField("Comments", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                            }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == icon ? .blue : .gray)
                                    .padding(8)
                                    .background(selectedIcon == icon ? Color.blue.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                
                Section("Location") {
                    Text("Latitude: \(waypoint.coordinate.latitude, specifier: "%.6f")")
                        .font(.system(.body, design: .monospaced))
                    Text("Longitude: \(waypoint.coordinate.longitude, specifier: "%.6f")")
                        .font(.system(.body, design: .monospaced))
                }
                
                Section("Dates") {
                    Text("Created: \(waypoint.createdDate, style: .date) at \(waypoint.createdDate, style: .time)")
                        .foregroundColor(.gray)
                    Text("Last Updated: \(waypoint.lastUpdatedDate, style: .date) at \(waypoint.lastUpdatedDate, style: .time)")
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Edit Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        waypointManager.updateWaypoint(
                            id: waypoint.id,
                            name: name,
                            comments: comments,
                            iconName: selectedIcon
                        )
                        
                        if let updatedWaypoint = waypointManager.savedWaypoints.first(where: { $0.id == waypoint.id }) {
                            selectedWaypoint = updatedWaypoint
                        }
                        
                        dismiss()
                    }
                }
            }
        }
    }
}