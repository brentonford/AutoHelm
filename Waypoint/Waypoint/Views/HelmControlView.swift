import SwiftUI
import CoreLocation

struct HelmControlView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var spotLockController: SpotLockController
    
    private var canNavigate: Bool {
        bluetooth.connectionState == .connected &&
        bluetooth.sensorData?.isNavigationReady == true
    }
    
    private var bearing: Double? {
        guard let sensors = bluetooth.sensorData,
              let lockPos = spotLockController.lockPosition else { return nil }
        return sensors.currentLocation.bearing(to: lockPos)
    }

    var body: some View {
        List {
            motorControlSection
            spotLockSection
            connectionSection
            gpsStatusSection
            compassSection
        }
        .navigationTitle("Helm Control")
        .toolbar {
            StatusToolbar(bluetooth: bluetooth)
        }
    }
    
    private var motorControlSection: some View {
        Section {
            ManualMotorControls(bluetooth: bluetooth) {
                Task {
                    await spotLockController.disengage()
                }
            }
        } header: {
            Text("Manual Remote Control")
        } footer: {
            Text("Manual control automatically disables Spot Lock")
        }
    }
    
    private var spotLockSection: some View {
        Section {
            SpotLockControls(
                spotLockController: spotLockController,
                canNavigate: canNavigate,
                onEngageHere: {
                    Task {
                        guard let sensors = bluetooth.sensorData else { return }
                        await spotLockController.engage(at: sensors.currentLocation)
                    }
                },
                onEngageAtWaypoint: {
                    // Waypoint functionality removed
                },
                onDisengage: {
                    Task {
                        await spotLockController.disengage()
                    }
                },
                onJogStart: { direction in
                    spotLockController.jogStart(direction: direction)
                },
                onJogStop: {
                    spotLockController.jogStop()
                }
            )
            
            if spotLockController.isActive, let sensors = bluetooth.sensorData {
                Divider()
                
                LabeledContent("Current Heading") {
                    Text(String(format: "%.1f°", sensors.heading))
                        .foregroundColor(.blue)
                }
                
                if let bearing = bearing {
                    LabeledContent("Bearing to Lock") {
                        Text(String(format: "%.1f° %@", bearing, cardinalDirection(for: bearing)))
                            .foregroundColor(.green)
                    }
                    
                    LabeledContent("Relative Angle") {
                        let relativeAngle = calculateRelativeAngle(
                            currentHeading: sensors.heading,
                            targetBearing: bearing
                        )
                        Text(String(format: "%.1f°", relativeAngle))
                            .foregroundColor(abs(relativeAngle) > 15 ? .orange : .green)
                    }
                }
            }
        } header: {
            Text("Spot Lock")
        } footer: {
            Text("Maintains position within 2m radius with automatic corrections")
        }
    }
    
    private var connectionSection: some View {
        Section("Helm Device") {
            ConnectionStatus(bluetooth: bluetooth)
            
            if !bluetooth.commandHistory.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Commands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(bluetooth.commandHistory) { entry in
                        HStack {
                            Text(entry.command)
                                .font(.caption.monospaced())
                                .foregroundColor(.primary)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
    
    private var gpsStatusSection: some View {
        Section("GPS Status") {
            if let sensors = bluetooth.sensorData {
                GpsStatusView(sensors: sensors)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var compassSection: some View {
        Section("Compass") {
            if let sensors = bluetooth.sensorData {
                CompassStatusView(sensors: sensors)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5) / 45.0) % 8
        return directions[index]
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

#Preview {
    HelmControlView()
        .environmentObject(BluetoothManager())
        .environmentObject(SpotLockController(bluetooth: BluetoothManager()))
}