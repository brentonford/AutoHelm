import SwiftUI
import SwiftData
import CoreLocation

struct NewWaypointSheet: View {
    let coordinate: CLLocationCoordinate2D
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var isGeocoding = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    if isGeocoding {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Getting location name…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Name", text: $name)
                    }
                    Text(String(format: "%.6f, %.6f",
                                coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isGeocoding)
                }
            }
            .task {
                name = await GeocodingService.shared.locationName(for: coordinate)
                isGeocoding = false
            }
        }
    }

    private func save() {
        let wp = Waypoint(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        wp.notes = notes
        context.insert(wp)
        dismiss()
    }
}
