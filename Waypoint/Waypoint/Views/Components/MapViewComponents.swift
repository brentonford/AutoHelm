import SwiftUI
import MapKit
import CoreLocation

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

struct SelectedWaypointCard: View {
    let waypoint: Waypoint
    let isSpotLockActive: Bool
    let sensorData: SensorData?
    let canNavigate: Bool
    let onEngageSpotLock: () -> Void
    let onDisengageSpotLock: () -> Void
    
    @State private var showingInitWarning = false
    
    private var distance: Double? {
        guard let sensors = sensorData else { return nil }
        let currentLocation = sensors.currentLocation
        return currentLocation.distance(to: waypoint.coordinate)
    }
    
    private var bearing: Double? {
        guard let sensors = sensorData else { return nil }
        let currentLocation = sensors.currentLocation
        return currentLocation.bearing(to: waypoint.coordinate)
    }
    
    private var estimatedTime: TimeInterval? {
        guard let distance else { return nil }
        let averageSpeed = 1.0
        return distance / averageSpeed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            waypointInfoRow
            spotLockButton
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
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
            
            if isSpotLockActive {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                    Text("Spot Lock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }
    
    private var waypointInfoRow: some View {
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
                    Text("\(Int(bearing))° \(cardinalDirection(for: bearing))")
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
    }
    
    private var spotLockButton: some View {
        VStack(spacing: 8) {
            if isSpotLockActive {
                Button {
                    onDisengageSpotLock()
                } label: {
                    HStack {
                        Image(systemName: "pin.slash.fill")
                        Text("Disengage Spot Lock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.red)
            }
        }
    }
    
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

struct QuickSpotLockButton: View {
    let canNavigate: Bool
    let onEngage: () -> Void
    
    @State private var showingInitWarning = false
    
    var body: some View {
        Button {
            showingInitWarning = true
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
        .alert("Motor Initialization Required", isPresented: $showingInitWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") {
                onEngage()
            }
        } message: {
            Text("Before engaging Spot Lock, ensure the electric motor is:\n\n• Motor is ON\n• Speed is set to 0\n\nSpot Lock will only control speed levels.")
        }
    }
}

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