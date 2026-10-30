import SwiftUI
import SwiftData

@main
struct WaypointApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(makeContainer())
    }
}

private func makeContainer() -> ModelContainer {
    do {
        let waypointConfig = ModelConfiguration(
            "waypoints",
            schema: Schema([Waypoint.self, WaypointPhoto.self])
        )
        let trackConfig = ModelConfiguration(
            "tracks",
            schema: Schema([Track.self, TrackPoint.self])
        )
        return try ModelContainer(
            for: Schema([Waypoint.self, WaypointPhoto.self, Track.self, TrackPoint.self]),
            configurations: waypointConfig, trackConfig
        )
    } catch {
        fatalError("[SwiftData] Cannot create model container: \(error)")
    }
}
