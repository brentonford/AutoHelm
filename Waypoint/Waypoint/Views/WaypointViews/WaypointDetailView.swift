import SwiftUI
import CoreLocation

struct WaypointDetailView: View {
    let waypoint: Waypoint
    let onSend: (CLLocationCoordinate2D) -> Void
    let onDelete: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    @State private var name: String
    @State private var comments: String
    @State private var showingDeleteAlert = false
    
    init(waypoint: Waypoint, onSend: @escaping (CLLocationCoordinate2D) -> Void, onDelete: @escaping (Waypoint) -> Void) {
        self.waypoint = waypoint
        self.onSend = onSend
        self.onDelete = onDelete
        self._name = State(initialValue: waypoint.name)
        self._comments = State(initialValue: waypoint.comments)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Waypoint Information") {
                    HStack {
                        Image(systemName: waypoint.iconName)
                            .foregroundColor(.blue)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading) {
                            TextField("Waypoint Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Comments (Optional)", text: $comments)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                Section("Location") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text(String(format: "%.6f", waypoint.coordinate.latitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text(String(format: "%.6f", waypoint.coordinate.longitude))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Details") {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(waypoint.createdDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    
                    if waypoint.lastUpdatedDate != waypoint.createdDate {
                        HStack {
                            Text("Modified")
                            Spacer()
                            Text(waypoint.lastUpdatedDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Actions") {
                    Button(action: {
                        onSend(waypoint.coordinate)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(bluetoothManager.isConnected ? .white : .gray)
                            Text("Send to Helm Device")
                                .foregroundColor(bluetoothManager.isConnected ? .white : .gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bluetoothManager.isConnected ? .blue : .gray.opacity(0.3))
                        .cornerRadius(8)
                    }
                    .disabled(!bluetoothManager.isConnected)
                    
                    if !bluetoothManager.isConnected {
                        Text("Connect to Helm device to send waypoints")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Waypoint")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Waypoint Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Waypoint", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    onDelete(waypoint)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete '\(waypoint.name)'? This action cannot be undone.")
            }
        }
    }
}

#Preview {
    WaypointDetailView(
        waypoint: Waypoint(
            coordinate: CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153),
            name: "Sydney Opera House",
            comments: "Iconic landmark"
        ),
        onSend: { _ in },
        onDelete: { _ in }
    )
    .environmentObject(BluetoothManager())
}