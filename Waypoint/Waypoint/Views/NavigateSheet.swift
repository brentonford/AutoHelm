import SwiftUI
import CoreLocation

struct NavigateSheet: View {
    let waypoint: Waypoint
    @EnvironmentObject private var navController: WaypointNavController
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var speedLevel: Double = 5

    private var helmCoordinate: CLLocationCoordinate2D? {
        guard let d = bluetooth.sensorData, d.hasFix else { return nil }
        return d.currentLocation
    }

    private var distanceText: String? {
        guard let helm = helmCoordinate else { return nil }
        let m = waypoint.distanceMetres(from: helm)
        return m < 1000
            ? String(format: "%.0f m", m)
            : String(format: "%.2f km", m / 1000)
    }

    private var currentSpeedKmh: String? {
        guard let d = bluetooth.sensorData, d.speedKmh > 0.1 else { return nil }
        return String(format: "%.1f km/hr", d.speedKmh)
    }

    private var canNavigate: Bool {
        bluetooth.connectionState == .connected &&
        (bluetooth.sensorData?.isNavigationReady ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Destination", value: waypoint.name)
                    if let dist = distanceText {
                        LabeledContent("Distance", value: dist)
                    }
                    if let kmh = currentSpeedKmh {
                        LabeledContent("Current Speed", value: kmh)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Motor Level")
                            Spacer()
                            Text("\(Int(speedLevel))")
                                .font(.headline)
                                .monospacedDigit()
                        }
                        Slider(value: $speedLevel, in: 1...10, step: 1)
                            .tint(.orange)
                        HStack {
                            Text("Slow").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Fast").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Cruising Speed")
                } footer: {
                    Text("The motor slows automatically within 10 m of the destination, then Spot Lock holds position on arrival. Live speed in km/hr is shown on the map during navigation.")
                }

                if !canNavigate {
                    Section {
                        Label(
                            bluetooth.connectionState == .connected
                                ? "GPS fix required to navigate"
                                : "Connect to Helm to navigate",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Navigate to Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        navController.navigate(to: waypoint, speedLevel: Int(speedLevel))
                        dismiss()
                    }
                    .disabled(!canNavigate)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
