import Foundation
import Combine
import SwiftData
import CoreLocation

/// Records GPS breadcrumb tracks while the Helm is connected.
/// Appends one TrackPoint every 5 seconds when a GPS fix is available.
/// Tracks with fewer than 2 points are discarded on disconnect.
@MainActor
final class TrackRecorder: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var activeTrack: Track?
    /// Pre-sorted coordinate cache — updated on every appended point, avoids O(n log n) sort per render.
    @Published private(set) var activeTrackCoordinates: [CLLocationCoordinate2D] = []

    // MARK: - Private

    private let bluetooth: BluetoothManager
    private var context: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: AnyCancellable?
    private static let recordingInterval: TimeInterval = 5

    // MARK: - Init

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        observeConnection()
    }

    deinit {
        cancellables.removeAll()
        recordingTimer?.cancel()
    }

    /// Called once the SwiftData model context is available (from a View's .task).
    /// If the device is already connected when this is called, recording starts immediately.
    func setContext(_ context: ModelContext) {
        self.context = context
        if bluetooth.connectionState == .connected {
            startRecording()
        }
    }

    // MARK: - Observe BLE connection

    private func observeConnection() {
        bluetooth.$connectionState
            .sink { [weak self] state in
                guard let self else { return }
                if state == .connected {
                    self.startRecording()
                } else {
                    self.stopRecording()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard !isRecording, let context else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        let track = Track(name: "Track \(formatter.string(from: Date()))")
        context.insert(track)
        activeTrack = track
        isRecording = true

        recordingTimer = Timer.publish(every: Self.recordingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.appendPoint() }
    }

    private func stopRecording() {
        guard isRecording else { return }
        recordingTimer?.cancel()
        recordingTimer = nil
        isRecording = false
        activeTrackCoordinates = []

        if let track = activeTrack {
            if (track.points?.count ?? 0) < 2 {
                context?.delete(track)
            } else {
                track.distanceMetres = track.totalDistanceMetres  // cache before finalizing
                track.dateEnded = Date()
            }
        }
        activeTrack = nil
    }

    // MARK: - Point recording

    private func appendPoint() {
        guard let sensors = bluetooth.sensorData,
              sensors.hasFix,
              let track = activeTrack else { return }

        let coord = sensors.currentLocation
        let point = TrackPoint(
            latitude:  coord.latitude,
            longitude: coord.longitude,
            speedKmh:  sensors.speedKmh
        )
        context?.insert(point)
        track.points?.append(point)
        activeTrackCoordinates.append(coord)
    }
}
