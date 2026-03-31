import SwiftUI
import SwiftData
import CoreLocation
import UniformTypeIdentifiers
import UIKit

struct WaypointListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var bluetooth: BluetoothManager

    @Query(sort: \Waypoint.dateCreated, order: .reverse) private var allWaypoints: [Waypoint]

    @State private var searchText       = ""
    @State private var sortOrder        = WaypointSortOrder.dateDesc
    @State private var exportURL:      URL?
    @State private var showExporter    = false
    @State private var showImporter    = false
    @State private var importError: String?
    @State private var showImportError = false

    private var helmCoordinate: CLLocationCoordinate2D? {
        guard let d = bluetooth.sensorData, d.hasFix else { return nil }
        return d.currentLocation
    }

    private var displayed: [Waypoint] {
        let q = searchText.lowercased()
        let base: [Waypoint] = q.isEmpty
            ? allWaypoints
            : allWaypoints.filter {
                $0.name.lowercased().contains(q) || $0.notes.lowercased().contains(q)
            }
        switch sortOrder {
        case .dateDesc: return base
        case .dateAsc:  return base.reversed()
        case .name:     return base.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .distance:
            guard let helm = helmCoordinate else { return base }
            return base.sorted { $0.distanceMetres(from: helm) < $1.distanceMetres(from: helm) }
        }
    }

    var body: some View {
        List {
            ForEach(displayed) { waypoint in
                NavigationLink {
                    WaypointDetailView(waypoint: waypoint)
                } label: {
                    WaypointRow(waypoint: waypoint, helmCoordinate: helmCoordinate)
                }
            }
            .onDelete(perform: delete)
        }
        .searchable(text: $searchText, prompt: "Search waypoints")
        .navigationTitle("Waypoints (\(allWaypoints.count))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { waypointMenu }
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
        .sheet(isPresented: $showExporter) { exportSheet }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Could not read the GPX file.")
        }
        .task { cleanupOrphanedPhotos() }
    }

    // MARK: - Toolbar

    private var waypointMenu: some View {
        Menu {
            sortPicker
            Divider()
            exportButton
            importButton
        } label: {
            Label("Menu", systemImage: "ellipsis.circle")
        }
    }

    private var sortPicker: some View {
        Picker("Sort by", selection: $sortOrder) {
            ForEach(WaypointSortOrder.allCases) { order in
                Text(order.label).tag(order)
            }
        }
    }

    private var exportButton: some View {
        Button {
            exportGPX()
        } label: {
            Label("Export GPX", systemImage: "square.and.arrow.up")
        }
        .disabled(allWaypoints.isEmpty)
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Label("Import GPX", systemImage: "square.and.arrow.down")
        }
    }

    // MARK: - Export sheet

    @ViewBuilder
    private var exportSheet: some View {
        if let url = exportURL {
            // Present UIActivityViewController directly — avoids nested sheet
            // that would result from placing a ShareLink inside a .sheet.
            ActivityView(items: [url])
        }
    }

    // MARK: - Helpers

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            let wp = displayed[i]
            wp.photos?.forEach { WaypointPhotoStore.shared.delete(filename: $0.filename) }
            context.delete(wp)
        }
    }

    private func exportGPX() {
        guard let url = GPXService.exportGPX(waypoints: allWaypoints) else { return }
        exportURL    = url
        showExporter = true
    }

    // M3: Clean up photo files that have no matching WaypointPhoto model record.
    private func cleanupOrphanedPhotos() {
        let knownFilenames = Set(allWaypoints.flatMap { $0.photos?.map(\.filename) ?? [] })
        WaypointPhotoStore.shared.cleanupOrphans(keeping: knownFilenames)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
            showImportError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let imported = GPXService.importGPX(from: url)
            if imported.isEmpty {
                importError = "No valid waypoints found in the file."
                showImportError = true
                return
            }
            // Deduplicate: skip waypoints whose name + rounded coordinate already exist.
            let existingKeys = Set(allWaypoints.map { dedupeKey($0.name, $0.latitude, $0.longitude) })
            var inserted = 0
            for item in imported {
                let key = dedupeKey(item.name, item.latitude, item.longitude)
                guard !existingKeys.contains(key) else { continue }
                let wp = Waypoint(name: item.name, latitude: item.latitude, longitude: item.longitude)
                wp.notes = item.notes
                wp.dateCreated = item.date
                context.insert(wp)
                inserted += 1
            }
            if inserted == 0 {
                importError = "All waypoints in this file already exist."
                showImportError = true
            }
        }
    }

    /// Deduplication key: name + coordinate rounded to ~11 m (~4 decimal places).
    private func dedupeKey(_ name: String, _ lat: Double, _ lon: Double) -> String {
        String(format: "%@|%.4f|%.4f", name, lat, lon)
    }
}

// MARK: - Supporting types

enum WaypointSortOrder: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, name, distance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc: return "Newest First"
        case .dateAsc:  return "Oldest First"
        case .name:     return "Name"
        case .distance: return "Distance"
        }
    }
}

private struct WaypointRow: View {
    let waypoint: Waypoint
    let helmCoordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(waypoint.name)
                .font(.headline)

            HStack(spacing: 12) {
                if let helm = helmCoordinate {
                    Label(formatDist(waypoint.distanceMetres(from: helm)),
                          systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(waypoint.dateCreated.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !(waypoint.photos?.isEmpty ?? true) {
                    Label("\(waypoint.photos?.count ?? 0)", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !waypoint.notes.isEmpty {
                Text(waypoint.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDist(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.1f km", m / 1000)
    }
}

// MARK: - ActivityView (M1: direct share sheet, avoids nested sheet from ShareLink-in-sheet)

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
