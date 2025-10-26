import SwiftUI
import CoreLocation

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
        VStack(alignment: .leading, spacing: 6) {
            WaypointDetailHeader(
                waypoint: waypoint,
                onClose: { selectedWaypoint = nil }
            )
            
            if !isNavigationEnabled {
                NavigationDisabledWarning()
            }
            
            WaypointActionButtons(
                waypoint: waypoint,
                bluetoothManager: bluetoothManager,
                waypointManager: waypointManager,
                isNavigationEnabled: isNavigationEnabled,
                showEditSheet: $showEditSheet,
                showConfirmation: $showConfirmation,
                showDeleteConfirmation: $showDeleteConfirmation,
                waypointToDelete: $waypointToDelete,
                onUpdateWaypoint: { updatedWaypoint in
                    selectedWaypoint = updatedWaypoint
                }
            )
            
            if !bluetoothManager.isConnected && !waypoint.isSaved {
                ConnectionRequiredWarning()
            }
            
            if showConfirmation {
                WaypointConfirmationView()
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .sheet(isPresented: $showEditSheet) {
            EditWaypointView(
                waypoint: waypoint,
                waypointManager: waypointManager,
                selectedWaypoint: $selectedWaypoint
            )
        }
    }
}

// MARK: - Header Component
struct WaypointDetailHeader: View {
    let waypoint: Waypoint
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if waypoint.isSaved {
                    HStack {
                        Image(systemName: waypoint.iconName)
                            .foregroundColor(.blue)
                        Text(waypoint.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("Selected Waypoint")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                CoordinateDisplay(coordinate: waypoint.coordinate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Coordinate Display
struct CoordinateDisplay: View {
    let coordinate: CLLocationCoordinate2D
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(coordinate.latitude, specifier: "%.4f")")
                .font(.system(.caption2, design: .monospaced))
            Text("\(coordinate.longitude, specifier: "%.4f")")
                .font(.system(.caption2, design: .monospaced))
        }
    }
}

// MARK: - Navigation Disabled Warning
struct NavigationDisabledWarning: View {
    var body: some View {
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
}

// MARK: - Connection Required Warning
struct ConnectionRequiredWarning: View {
    var body: some View {
        Text("Connect to Helm device to send waypoint")
            .font(.caption)
            .foregroundColor(.orange)
            .italic()
    }
}

// MARK: - Confirmation View
struct WaypointConfirmationView: View {
    var body: some View {
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
}

// MARK: - Action Buttons Component
struct WaypointActionButtons: View {
    let waypoint: Waypoint
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    let isNavigationEnabled: Bool
    @Binding var showEditSheet: Bool
    @Binding var showConfirmation: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var waypointToDelete: Waypoint?
    let onUpdateWaypoint: (Waypoint) -> Void
    
    var body: some View {
        if waypoint.isSaved {
            SavedWaypointButtons(
                waypoint: waypoint,
                bluetoothManager: bluetoothManager,
                showEditSheet: $showEditSheet,
                showConfirmation: $showConfirmation,
                showDeleteConfirmation: $showDeleteConfirmation,
                waypointToDelete: $waypointToDelete
            )
        } else {
            NewWaypointButtons(
                waypoint: waypoint,
                bluetoothManager: bluetoothManager,
                waypointManager: waypointManager,
                showConfirmation: $showConfirmation,
                onUpdateWaypoint: onUpdateWaypoint
            )
        }
    }
}

// MARK: - Saved Waypoint Buttons
struct SavedWaypointButtons: View {
    let waypoint: Waypoint
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var showEditSheet: Bool
    @Binding var showConfirmation: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var waypointToDelete: Waypoint?
    
    var body: some View {
        HStack(spacing: 6) {
            EditButton(showEditSheet: $showEditSheet)
            
            if bluetoothManager.isConnected {
                SendButton(waypoint: waypoint, bluetoothManager: bluetoothManager, showConfirmation: $showConfirmation)
            }
            
            DeleteButton(waypoint: waypoint, showDeleteConfirmation: $showDeleteConfirmation, waypointToDelete: $waypointToDelete)
        }
    }
}

// MARK: - New Waypoint Buttons
struct NewWaypointButtons: View {
    let waypoint: Waypoint
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var waypointManager: WaypointManager
    @Binding var showConfirmation: Bool
    let onUpdateWaypoint: (Waypoint) -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            if bluetoothManager.isConnected {
                SendButton(waypoint: waypoint, bluetoothManager: bluetoothManager, showConfirmation: $showConfirmation)
            }
            
            SaveButton(waypoint: waypoint, waypointManager: waypointManager, onUpdateWaypoint: onUpdateWaypoint)
            
            Spacer()
        }
    }
}

// MARK: - Individual Button Components
struct EditButton: View {
    @Binding var showEditSheet: Bool
    
    var body: some View {
        Button(action: { showEditSheet = true }) {
            Image(systemName: "pencil")
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
    }
}

struct SendButton: View {
    let waypoint: Waypoint
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var showConfirmation: Bool
    
    var body: some View {
        Button(action: sendWaypoint) {
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                    .font(.caption2)
                Text(waypoint.isSaved ? "Send" : "Send to Helm")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
    
    private func sendWaypoint() {
        bluetoothManager.sendWaypoint(
            latitude: waypoint.coordinate.latitude,
            longitude: waypoint.coordinate.longitude
        )
        bluetoothManager.setNavigationEnabled(true)
        showConfirmation = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showConfirmation = false
        }
    }
}

struct SaveButton: View {
    let waypoint: Waypoint
    @ObservedObject var waypointManager: WaypointManager
    let onUpdateWaypoint: (Waypoint) -> Void
    
    var body: some View {
        Button(action: saveWaypoint) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                Text("Save")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
    
    private func saveWaypoint() {
        waypointManager.saveWaypoint(waypoint)
        if let savedWaypoint = waypointManager.savedWaypoints.last {
            onUpdateWaypoint(savedWaypoint)
        }
    }
}

struct DeleteButton: View {
    let waypoint: Waypoint
    @Binding var showDeleteConfirmation: Bool
    @Binding var waypointToDelete: Waypoint?
    
    var body: some View {
        Button(action: {
            waypointToDelete = waypoint
            showDeleteConfirmation = true
        }) {
            Image(systemName: "trash.fill")
                .font(.caption)
                .padding(8)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(6)
        }
    }
}