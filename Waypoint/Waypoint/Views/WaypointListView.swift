import SwiftUI
import CoreLocation

enum WaypointSortOrder {
    case nameAscending
    case nameDescending
    case dateCreatedNewest
    case dateCreatedOldest
    case dateModifiedNewest
    case dateModifiedOldest
}

struct WaypointListView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @Binding var waypoints: [Waypoint]
    @Binding var selectedWaypoint: Waypoint?
    
    @State private var searchText = ""
    @State private var sortOrder: WaypointSortOrder = .dateCreatedNewest
    @State private var showingSortMenu = false
    @State private var editingWaypoint: Waypoint?
    @State private var showingEditSheet = false
    @Environment(\.dismiss) var dismiss
    
    var filteredAndSortedWaypoints: [Waypoint] {
        let filtered = searchText.isEmpty ? waypoints : waypoints.filter { waypoint in
            waypoint.name.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOrder {
        case .nameAscending:
            return filtered.sorted { $0.name < $1.name }
        case .nameDescending:
            return filtered.sorted { $0.name > $1.name }
        case .dateCreatedNewest:
            return filtered.sorted { $0.dateCreated > $1.dateCreated }
        case .dateCreatedOldest:
            return filtered.sorted { $0.dateCreated < $1.dateCreated }
        case .dateModifiedNewest:
            return filtered.sorted { $0.dateModified > $1.dateModified }
        case .dateModifiedOldest:
            return filtered.sorted { $0.dateModified < $1.dateModified }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredAndSortedWaypoints) { waypoint in
                    WaypointRow(
                        waypoint: waypoint,
                        isSelected: selectedWaypoint?.id == waypoint.id,
                        onSelect: {
                            selectedWaypoint = waypoint
                        },
                        onEdit: {
                            editingWaypoint = waypoint
                            showingEditSheet = true
                        },
                        onSendToHelm: {
                            sendWaypoint(waypoint)
                        },
                        onDelete: {
                            deleteWaypoint(waypoint)
                        }
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search waypoints")
            .navigationTitle("Waypoints")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Sort By") {
                            Button {
                                sortOrder = .dateCreatedNewest
                            } label: {
                                Label("Created (Newest)", systemImage: sortOrder == .dateCreatedNewest ? "checkmark" : "")
                            }
                            
                            Button {
                                sortOrder = .dateCreatedOldest
                            } label: {
                                Label("Created (Oldest)", systemImage: sortOrder == .dateCreatedOldest ? "checkmark" : "")
                            }
                            
                            Button {
                                sortOrder = .dateModifiedNewest
                            } label: {
                                Label("Modified (Newest)", systemImage: sortOrder == .dateModifiedNewest ? "checkmark" : "")
                            }
                            
                            Button {
                                sortOrder = .dateModifiedOldest
                            } label: {
                                Label("Modified (Oldest)", systemImage: sortOrder == .dateModifiedOldest ? "checkmark" : "")
                            }
                            
                            Button {
                                sortOrder = .nameAscending
                            } label: {
                                Label("Name (A-Z)", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                            }
                            
                            Button {
                                sortOrder = .nameDescending
                            } label: {
                                Label("Name (Z-A)", systemImage: sortOrder == .nameDescending ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let waypoint = editingWaypoint {
                    EditWaypointSheet(waypoint: waypoint) { updatedWaypoint in
                        if let index = waypoints.firstIndex(where: { $0.id == updatedWaypoint.id }) {
                            waypoints[index] = updatedWaypoint
                            if selectedWaypoint?.id == updatedWaypoint.id {
                                selectedWaypoint = updatedWaypoint
                            }
                        }
                        showingEditSheet = false
                    } onCancel: {
                        showingEditSheet = false
                    }
                }
            }
        }
    }
    
    private func sendWaypoint(_ waypoint: Waypoint) {
        guard bluetooth.connectionState == .connected else { return }
        selectedWaypoint = waypoint
        bluetooth.sendWaypoint(waypoint)
        bluetooth.enableNavigation()
        dismiss()
    }
    
    private func deleteWaypoint(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        if selectedWaypoint?.id == waypoint.id {
            selectedWaypoint = nil
        }
    }
}

struct WaypointRow: View {
    let waypoint: Waypoint
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onSendToHelm: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(waypoint.name)
                        .font(.headline)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(String(format: "%.6f, %.6f", waypoint.coordinate.latitude, waypoint.coordinate.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created: \(waypoint.dateCreated, style: .date) \(waypoint.dateCreated, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Modified: \(waypoint.dateModified, style: .date) \(waypoint.dateModified, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: onSendToHelm) {
                        Image(systemName: "paperplane")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct EditWaypointSheet: View {
    let waypoint: Waypoint
    let onSave: (Waypoint) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    
    init(waypoint: Waypoint, onSave: @escaping (Waypoint) -> Void, onCancel: @escaping () -> Void) {
        self.waypoint = waypoint
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: waypoint.name)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Waypoint name", text: $name)
                }
                
                Section("Location") {
                    Text(String(format: "%.6f, %.6f", waypoint.coordinate.latitude, waypoint.coordinate.longitude))
                        .foregroundColor(.secondary)
                }
                
                Section("Details") {
                    LabeledContent("Created") {
                        Text(waypoint.dateCreated, style: .date)
                        Text(waypoint.dateCreated, style: .time)
                    }
                    
                    LabeledContent("Modified") {
                        Text(waypoint.dateModified, style: .date)
                        Text(waypoint.dateModified, style: .time)
                    }
                }
            }
            .navigationTitle("Edit Waypoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = waypoint
                        updated.updateName(name)
                        onSave(updated)
                    }
                }
            }
        }
    }
}