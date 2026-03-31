import SwiftUI
import SwiftData

struct TrackListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var trackRecorder: TrackRecorder

    @Query(sort: \Track.dateStarted, order: .reverse) private var tracks: [Track]

    var body: some View {
        List {
            if trackRecorder.isRecording {
                recordingBanner
            }

            ForEach(tracks) { track in
                TrackRow(track: track)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Tracks (\(tracks.count))")
        .toolbar { EditButton() }
        .overlay {
            if tracks.isEmpty && !trackRecorder.isRecording {
                ContentUnavailableView(
                    "No Tracks Yet",
                    systemImage: "wake.indicator",
                    description: Text("Tracks are recorded automatically while connected to the Helm.")
                )
            }
        }
    }

    // MARK: - Subviews

    private var recordingBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text("Recording track…")
                .font(.subheadline)
                .foregroundStyle(.primary)
            if let track = trackRecorder.activeTrack {
                Spacer()
                Text(formatDist(track.totalDistanceMetres))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(tracks[i]) }
    }

    private func formatDist(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.1f km", m / 1000)
    }
}

private struct TrackRow: View {
    let track: Track

    /// True when the track has no end date — it was interrupted by a force-kill or crash.
    private var wasInterrupted: Bool { track.dateEnded == nil && !(track.points?.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(track.name)
                    .font(.headline)
                if wasInterrupted {
                    Label("Interrupted", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                Label(track.dateStarted.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !wasInterrupted {
                    Label(formatDuration(track.durationSeconds),
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(formatDist(track.totalDistanceMetres),
                      systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(track.points?.count ?? 0) points")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func formatDist(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.1f km", m / 1000)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
