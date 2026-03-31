import SwiftUI
import SwiftData
import PhotosUI

struct WaypointDetailView: View {
    @Bindable var waypoint: Waypoint
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var navController: WaypointNavController

    @State private var pickerItem: PhotosPickerItem?
    @State private var fullScreenPhoto: WaypointPhoto?
    @State private var showDeleteConfirm = false
    @State private var showNavigateSheet = false

    private var canNavigate: Bool {
        bluetooth.connectionState == .connected &&
        (bluetooth.sensorData?.isNavigationReady ?? false)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $waypoint.name)
                TextField("Notes", text: $waypoint.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Location") {
                LabeledContent("Coordinates") {
                    Text(String(format: "%.6f, %.6f",
                                waypoint.latitude, waypoint.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Added") {
                    Text(waypoint.dateCreated.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Photos (\(waypoint.photos?.count ?? 0))") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Add Photo", systemImage: "plus")
                }
                .onChange(of: pickerItem) { _, item in
                    Task { await addPhoto(item) }
                }

                if !(waypoint.photos?.isEmpty ?? true) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(waypoint.photos ?? []) { photo in
                                PhotoThumb(photo: photo,
                                           onTap:    { fullScreenPhoto = photo },
                                           onDelete: { removePhoto(photo) })
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
        }
        .navigationTitle(waypoint.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNavigateSheet = true
                } label: {
                    Label("Navigate", systemImage: "location.north.line.fill")
                }
                .tint(.orange)
                .disabled(!canNavigate)
                .help("Connect to Helm with a GPS fix to navigate")
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showNavigateSheet) {
            NavigateSheet(waypoint: waypoint)
        }
        .sheet(item: $fullScreenPhoto) { photo in
            FullPhotoView(photo: photo)
        }
        .confirmationDialog("Delete \"\(waypoint.name)\"?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete Waypoint", role: .destructive) { deleteWaypoint() }
        }
    }

    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data   = try? await item.loadTransferable(type: Data.self),
              let uiImg  = UIImage(data: data),
              let result = WaypointPhotoStore.shared.save(uiImg)
        else { pickerItem = nil; return }

        let photo = WaypointPhoto(filename: result.filename, thumbnailData: result.thumbnail)
        context.insert(photo)
        // Save before assigning the relationship — avoids the iOS 18 CloudKit reversion bug
        // where an unsaved child record causes the relationship to roll back after ~15 seconds.
        try? context.save()
        waypoint.photos?.append(photo)
        pickerItem = nil
    }

    private func removePhoto(_ photo: WaypointPhoto) {
        WaypointPhotoStore.shared.delete(filename: photo.filename)
        waypoint.photos?.removeAll { $0 === photo }
        context.delete(photo)
    }

    private func deleteWaypoint() {
        waypoint.photos?.forEach { WaypointPhotoStore.shared.delete(filename: $0.filename) }
        context.delete(waypoint)
        dismiss()
    }
}

private struct PhotoThumb: View {
    let photo: WaypointPhoto
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImg = UIImage(data: photo.thumbnailData) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { onTap() }
            }
            Button { onDelete() } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .font(.title3)
            }
            .offset(x: 6, y: -6)
        }
    }
}

private struct FullPhotoView: View {
    let photo: WaypointPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let uiImg = WaypointPhotoStore.shared.load(filename: photo.filename) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea(.container, edges: .bottom)
                } else {
                    ContentUnavailableView("Photo Not Found", systemImage: "photo.slash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
