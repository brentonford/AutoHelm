import SwiftUI
import CoreLocation

struct WaypointListView: View {
    let waypoints: [Waypoint]
    let onSend: (Waypoint) -> Void
    let onDelete: (Waypoint) -> Void
    let onEdit: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    @State private var searchText = ""
    @State private var sortOrder = WaypointSortOrder.name
    
    enum WaypointSortOrder: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateModified = "Date Modified"
        
        var displayName: String { rawValue }
    }
    
    var filteredWaypoints: [Waypoint] {
        let filtered = waypoints.filter { waypoint in
            searchText.isEmpty ||
            waypoint.name.localizedCaseInsensitiveContains(searchText) ||
            waypoint.comments.localizedCaseInsensitiveContains(searchText)
        }
        
        return filtered.sorted { waypoint1, waypoint2 in
            switch sortOrder {
            case .name:
                return waypoint1.name < waypoint2.name
            case .dateCreated:
                return waypoint1.createdDate > waypoint2.createdDate
            case .dateModified:
                return waypoint1.lastUpdatedDate > waypoint2.lastUpdatedDate
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if waypoints.isEmpty {
                    emptyStateView
                } else {
                    waypointsList
                }
            }
            .navigationTitle("Waypoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(WaypointSortOrder.allCases, id: \.self) { order in
                            Button(order.displayName) {
                                sortOrder = order
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search waypoints")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Waypoints")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Tap on the map to create your first waypoint")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var waypointsList: some View {
        List {
            ForEach(filteredWaypoints) { waypoint in
                WaypointRowView(
                    waypoint: waypoint,
                    onSend: { onSend(waypoint) },
                    onEdit: { onEdit(waypoint) }
                )
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
                    
                    if bluetoothManager.isConnected {
                        Button {
                            onSend(waypoint)
                        } label: {
                            Label("Send", systemImage: "paperplane")
                        }
                        .tint(.green)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    onDelete(filteredWaypoints[index])
                }
            }
        }
    }
}

struct WaypointRowView: View {
    let waypoint: Waypoint
    let onSend: () -> Void
    let onEdit: () -> Void
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
                            .lineLimit(1)
                    }
                    
                    Text(coordinateString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !waypoint.comments.isEmpty {
                        Text(waypoint.comments)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(waypoint.createdDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button(action: onSend) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.caption)
                            Text("Send")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!bluetoothManager.isConnected)
                    
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.caption)
                            Text("Edit")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
    
    private var coordinateString: String {
        return String(format: "%.6f, %.6f", waypoint.coordinate.latitude, waypoint.coordinate.longitude)
    }
}

#Preview {
    WaypointListView(
        waypoints: [
            Waypoint(coordinate: CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153), name: "Sydney Opera House", comments: "Iconic landmark"),
            Waypoint(coordinate: CLLocationCoordinate2D(latitude: -33.8523, longitude: 151.2108), name: "Harbour Bridge")
        ],
        onSend: { _ in },
        onDelete: { _ in },
        onEdit: { _ in }
    )
    .environmentObject(BluetoothManager())
}