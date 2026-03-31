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
    // Try CloudKit-backed container first.
    // Requires iCloud capability and the "iCloud.AutoHelm.Waypoint" container
    // to be enabled in Signing & Capabilities in Xcode.
    do {
        let waypointConfig = ModelConfiguration(
            "waypoints",
            schema: Schema([Waypoint.self, WaypointPhoto.self]),
            cloudKitDatabase: .private("iCloud.AutoHelm.Waypoint")
        )
        // Tracks are local-only — too many points to sync efficiently via CloudKit.
        let trackConfig = ModelConfiguration(
            "tracks",
            schema: Schema([Track.self, TrackPoint.self])
        )
        return try ModelContainer(
            for: Schema([Waypoint.self, WaypointPhoto.self, Track.self, TrackPoint.self]),
            configurations: waypointConfig, trackConfig
        )
    } catch {
        // CloudKit unavailable (no iCloud account, capability not configured, etc.)
        // Fall back to local-only storage so the app remains functional.
        print("[SwiftData] CloudKit container failed (\(error)). Falling back to local storage.")
        do {
            return try ModelContainer(for: Waypoint.self, WaypointPhoto.self, Track.self, TrackPoint.self)
        } catch {
            fatalError("[SwiftData] Cannot create local model container: \(error)")
        }
    }
}
