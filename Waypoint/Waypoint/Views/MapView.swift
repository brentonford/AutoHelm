import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct MapView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var spotLockController: SpotLockController
    @EnvironmentObject private var navController: WaypointNavController
    @EnvironmentObject private var trackRecorder: TrackRecorder

    @Query(sort: \Waypoint.dateCreated, order: .reverse) private var waypoints: [Waypoint]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pendingPin: PendingPin?
    @State private var selectedWaypoint: Waypoint?
    /// Tracks the last time a waypoint pin was tapped so we can suppress a simultaneous long-press.
    @State private var lastPinTapDate: Date = .distantPast

    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return sensors.hasFix && sensors.isNavigationReady
    }

    private var isSpotLockActive: Bool { spotLockController.isActive }

    private var bearing: Double? {
        guard let sensors = bluetooth.sensorData,
              let lockPos = spotLockController.lockPosition else { return nil }
        return sensors.currentLocation.bearing(to: lockPos)
    }

    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((bearing + 11.25) / 22.5) % 16
        return directions[index]
    }

    var body: some View {
        ZStack {
            mapContent
            overlayControls
        }
        .toolbar {
            StatusToolbar(bluetooth: bluetooth)
        }
        .sheet(item: $pendingPin) { pin in
            NewWaypointSheet(coordinate: pin.coordinate)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedWaypoint) { waypoint in
            NavigationStack {
                WaypointDetailView(waypoint: waypoint)
            }
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Helm position
                if let sensors = bluetooth.sensorData, sensors.hasFix {
                    Annotation("Helm", coordinate: sensors.currentLocation) {
                        HelmDirectionIndicator(heading: sensors.heading)
                            .frame(width: 36, height: 36)
                    }
                }

                // Spot lock position
                if let lockPosition = spotLockController.lockPosition {
                    Annotation("Spot Lock", coordinate: lockPosition) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 40, height: 40)
                            Circle()
                                .stroke(Color.blue, lineWidth: 3)
                                .frame(width: 40, height: 40)
                            Image(systemName: "pin.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                    }
                }

                // Saved waypoints
                ForEach(waypoints) { waypoint in
                    Annotation(waypoint.name, coordinate: waypoint.coordinate, anchor: .bottom) {
                        WaypointPinView(
                            isTarget: navController.targetWaypoint?.persistentModelID == waypoint.persistentModelID
                        )
                        .onTapGesture {
                            lastPinTapDate = Date()
                            selectedWaypoint = waypoint
                        }
                    }
                }

                // Navigation route line
                if let helmLoc = bluetooth.sensorData?.currentLocation,
                   let target  = navController.targetWaypoint {
                    MapPolyline(coordinates: [helmLoc, target.coordinate])
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                }

                // Active breadcrumb track (live recording) — uses pre-sorted cache in TrackRecorder
                if trackRecorder.activeTrackCoordinates.count > 1 {
                    MapPolyline(coordinates: trackRecorder.activeTrackCoordinates)
                        .stroke(.cyan.opacity(0.8), lineWidth: 2)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .overlay {
                MapLongPressCapture { point in
                    guard Date().timeIntervalSince(lastPinTapDate) > 1.0 else { return }
                    if let coord = proxy.convert(point, from: .local) {
                        pendingPin = PendingPin(coordinate: coord)
                    }
                }
            }
        }
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        VStack {
            Spacer()
            if navController.isActive {
                navStatusCard.padding()
            } else if spotLockController.isActive {
                spotLockStatusCard.padding()
            } else {
                quickSpotLockButton.padding()
            }
        }
    }

    // MARK: - Navigation Status Card

    private var navStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: navController.isArriving
                      ? "arrow.down.circle.fill" : "location.north.line.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(navController.isArriving ? "Arriving…" : "Navigating")
                        .font(.headline)
                        .foregroundColor(.orange)
                    if let wp = navController.targetWaypoint {
                        Text(wp.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    navController.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }

            Divider()

            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.title3).foregroundColor(.orange)
                    Text(String(format: "%.0f m", navController.distanceMetres))
                        .font(.subheadline.bold())
                    Text("Distance").font(.caption2).foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.title3).foregroundColor(.orange)
                    Text("Level \(navController.currentSpeed)")
                        .font(.subheadline.bold())
                    Text("Motor").font(.caption2).foregroundColor(.secondary)
                }

                if let sensors = bluetooth.sensorData, sensors.speedKmh > 0.1 {
                    VStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle")
                            .font(.title3).foregroundColor(.green)
                        Text(String(format: "%.1f km/hr", sensors.speedKmh))
                            .font(.subheadline.bold())
                        Text("Speed").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var spotLockStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if spotLockController.isDisengaging {
                disengagingHeader
            } else {
                activeHeader
                Divider()
                statusMetrics
                if let sensors = bluetooth.sensorData {
                    Divider()
                    headingMetrics(sensors: sensors)
                }
                jogControls
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var disengagingHeader: some View {
        HStack {
            ProgressView().scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 4) {
                Text("Disengaging Spot Lock")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("Please wait while safely stopping")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var activeHeader: some View {
        HStack {
            Image(systemName: "pin.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Spot Lock Active")
                    .font(.headline)
                    .foregroundColor(.blue)
                if let lockPos = spotLockController.lockPosition {
                    Text(String(format: "%.6f, %.6f", lockPos.latitude, lockPos.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await spotLockController.disengage() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            .disabled(spotLockController.isDisengaging)
        }
    }

    private var statusMetrics: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.title3).foregroundColor(.blue)
                Text(String(format: "%.2f m", spotLockController.distanceFromLock))
                    .font(.subheadline.bold())
                Text("Distance").font(.caption2).foregroundColor(.secondary)
            }
            if let bearing {
                VStack(spacing: 4) {
                    Image(systemName: "safari.fill")
                        .font(.title3).foregroundColor(.green)
                    Text("\(Int(bearing))° \(cardinalDirection(for: bearing))")
                        .font(.subheadline.bold())
                    Text("Bearing").font(.caption2).foregroundColor(.secondary)
                }
            }
            VStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.title3)
                    .foregroundColor(spotLockController.isApplyingThrust ? .green : .orange)
                Text("Level \(spotLockController.currentSpeedLevel)")
                    .font(.subheadline.bold())
                Text("Speed").font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func headingMetrics(sensors: SensorData) -> some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.title3).foregroundColor(.blue)
                Text(String(format: "%.1f°", sensors.heading))
                    .font(.subheadline.bold())
                Text("Heading").font(.caption2).foregroundColor(.secondary)
            }
            if let bearing {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title3).foregroundColor(.orange)
                    Text(String(format: "%.1f°", calculateRelativeAngle(
                        currentHeading: sensors.heading, targetBearing: bearing)))
                        .font(.subheadline.bold())
                    Text("Relative").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var jogControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Text("Jog Position (Hold to move)")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 16) {
                    JogButton(direction: .left,    icon: "arrow.left",  label: "W",
                              onPress: { spotLockController.jogStart(direction: $0) },
                              onRelease: { spotLockController.jogStop() })
                    VStack(spacing: 8) {
                        JogButton(direction: .forward, icon: "arrow.up",   label: "N",
                                  onPress: { spotLockController.jogStart(direction: $0) },
                                  onRelease: { spotLockController.jogStop() })
                        JogButton(direction: .back,    icon: "arrow.down", label: "S",
                                  onPress: { spotLockController.jogStart(direction: $0) },
                                  onRelease: { spotLockController.jogStop() })
                    }
                    JogButton(direction: .right,   icon: "arrow.right", label: "E",
                              onPress: { spotLockController.jogStart(direction: $0) },
                              onRelease: { spotLockController.jogStop() })
                }
            }
            .padding()
            .disabled(spotLockController.isDisengaging)
            Spacer()
        }
    }

    private var quickSpotLockButton: some View {
        QuickSpotLockButton(
            canNavigate: canNavigate,
            isDisengaging: spotLockController.isDisengaging
        ) {
            Task {
                guard let sensors = bluetooth.sensorData else { return }
                await spotLockController.engage(at: sensors.currentLocation)
            }
        }
    }

    private func calculateRelativeAngle(currentHeading: Double, targetBearing: Double) -> Double {
        var angle = targetBearing - currentHeading
        while angle >  180 { angle -= 360 }
        while angle < -180 { angle += 360 }
        return angle
    }
}

// MARK: - Supporting Types

/// Wraps a coordinate so it can be used with `.sheet(item:)`.
private struct PendingPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Pin annotation for saved waypoints.
/// Active navigation target is shown in orange; others in green.
private struct WaypointPinView: View {
    var isTarget: Bool = false
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title)
            .foregroundStyle(.white, isTarget ? .orange : .green)
            .shadow(radius: 2)
            .scaleEffect(isTarget ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isTarget)
    }
}

/// UIViewRepresentable overlay that captures long-press gestures from UIKit,
/// so they co-exist cleanly with MapKit's own pan/zoom recognisers.
private struct MapLongPressCapture: UIViewRepresentable {
    let onLongPress: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let gr = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        gr.minimumPressDuration = 0.6
        gr.cancelsTouchesInView = false
        view.addGestureRecognizer(gr)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    final class Coordinator: NSObject {
        let onLongPress: (CGPoint) -> Void
        init(onLongPress: @escaping (CGPoint) -> Void) { self.onLongPress = onLongPress }

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            onLongPress(gr.location(in: gr.view))
        }
    }
}

// MARK: - Helm Direction Indicator (unchanged)

struct HelmDirectionIndicator: View {
    let heading: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            let circlePath = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
            context.fill(circlePath, with: .color(.blue))
            context.stroke(circlePath, with: .color(.white), lineWidth: 3)

            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(heading.isFinite ? heading : 0))
            context.translateBy(x: -center.x, y: -center.y)

            let arrowSize = radius * 0.6
            var arrow = Path()
            arrow.move(to: CGPoint(x: center.x, y: center.y - arrowSize))
            arrow.addLine(to: CGPoint(x: center.x - arrowSize * 0.5, y: center.y + arrowSize * 0.3))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y))
            arrow.addLine(to: CGPoint(x: center.x + arrowSize * 0.5, y: center.y + arrowSize * 0.3))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(.white))
        }
    }
}
