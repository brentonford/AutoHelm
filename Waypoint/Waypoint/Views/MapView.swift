import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var spotLockController: SpotLockController

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private var canNavigate: Bool {
        guard bluetooth.connectionState == .connected else { return false }
        guard let sensors = bluetooth.sensorData else { return false }
        return sensors.hasFix && sensors.isNavigationReady
    }
    
    private var isSpotLockActive: Bool {
        spotLockController.isActive
    }

    private var bearing: Double? {
        guard let sensors = bluetooth.sensorData,
        let lockPos = spotLockController.lockPosition else { return nil }
        let currentLocation = sensors.currentLocation
        return currentLocation.bearing(to: lockPos)
    }

    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
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
    }

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            if let sensors = bluetooth.sensorData, sensors.hasFix {
                let helmLocation = sensors.currentLocation
                Annotation("Helm", coordinate: helmLocation) {
                    HelmDirectionIndicator(heading: sensors.heading)
                        .frame(width: 36, height: 36)
                }
            }
            
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
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
    
    private var overlayControls: some View {
        VStack {
            Spacer()

            if spotLockController.isActive {
                spotLockStatusCard
                    .padding()
            } else {
                quickSpotLockButton
                    .padding()
            }
        }
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
            ProgressView()
                .scaleEffect(0.8)
            
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
                Task {
                    await spotLockController.disengage()
                }
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
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(String(format: "%.2f m", spotLockController.distanceFromLock))
                    .font(.subheadline.bold())
                Text("Distance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            
            VStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.title3)
                    .foregroundColor(spotLockController.isApplyingThrust ? .green : .orange)
                Text("Level \(spotLockController.currentSpeedLevel)")
                    .font(.subheadline.bold())
                Text("Speed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func headingMetrics(sensors: SensorData) -> some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(String(format: "%.1f°", sensors.heading))
                    .font(.subheadline.bold())
                Text("Heading")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let bearing = bearing {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f°", calculateRelativeAngle(
                        currentHeading: sensors.heading,
                        targetBearing: bearing
                    )))
                        .font(.subheadline.bold())
                    Text("Relative")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var jogControls: some View {
        HStack() {
            Spacer()

        VStack(spacing: 8) {
            Text("Jog Position (Hold to move)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                JogButton(direction: .left, icon: "arrow.left", label: "W", onPress: { dir in
                    spotLockController.jogStart(direction: dir)
                }, onRelease: {
                    spotLockController.jogStop()
                })
                
                VStack(spacing: 8) {
                    JogButton(direction: .forward, icon: "arrow.up", label: "N", onPress: { dir in
                        spotLockController.jogStart(direction: dir)
                    }, onRelease: {
                        spotLockController.jogStop()
                    })
                    
                    JogButton(direction: .back, icon: "arrow.down", label: "S", onPress: { dir in
                        spotLockController.jogStart(direction: dir)
                    }, onRelease: {
                        spotLockController.jogStop()
                    })
                }
                
                JogButton(direction: .right, icon: "arrow.right", label: "E", onPress: { dir in
                    spotLockController.jogStart(direction: dir)
                }, onRelease: {
                    spotLockController.jogStop()
                })
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
        while angle > 180 {
            angle -= 360
        }
        while angle < -180 {
            angle += 360
        }
        return angle
    }
}

struct HelmDirectionIndicator: View {
    let heading: Double
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            
            // Draw blue circle background
            let circlePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(circlePath, with: .color(.blue))
            context.stroke(circlePath, with: .color(.white), lineWidth: 3)
            
            // Apply rotation for heading
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(heading.isFinite ? heading : 0))
            context.translateBy(x: -center.x, y: -center.y)
            
            // Draw arrow pointing up (north) - rotation transforms it to heading
            let arrowSize = radius * 0.6
            var arrow = Path()
            arrow.move(to: CGPoint(x: center.x, y: center.y - arrowSize))  // Top point
            arrow.addLine(to: CGPoint(x: center.x - arrowSize * 0.5, y: center.y + arrowSize * 0.3))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y))
            arrow.addLine(to: CGPoint(x: center.x + arrowSize * 0.5, y: center.y + arrowSize * 0.3))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(.white))
        }
    }
}