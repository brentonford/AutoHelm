import SwiftUI
import CoreLocation

struct EditWaypointView: View {
    let waypoint: Waypoint
    @ObservedObject var waypointManager: WaypointManager
    @Binding var selectedWaypoint: Waypoint?
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var comments: String
    @State private var selectedIcon: String
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    private let availableIcons = [
        "mappin.circle.fill", "star.fill", "flag.fill", "house.fill",
        "anchor.fill", "sailboat.fill", "car.fill", "bicycle",
        "figure.walk", "mountain.2.fill", "tree.fill", "leaf.fill"
    ]
    
    init(waypoint: Waypoint, waypointManager: WaypointManager, selectedWaypoint: Binding<Waypoint?>) {
        self.waypoint = waypoint
        self.waypointManager = waypointManager
        self._selectedWaypoint = selectedWaypoint
        self._name = State(initialValue: waypoint.name)
        self._comments = State(initialValue: waypoint.comments)
        self._selectedIcon = State(initialValue: waypoint.iconName)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Waypoint Name", text: $name)
                    
                    TextField("Comments", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Location")) {
                    LocationInfoRow(label: "Latitude", value: waypoint.coordinate.latitude)
                    LocationInfoRow(label: "Longitude", value: waypoint.coordinate.longitude)
                    
                    Button("View on Map") {
                        // TODO: Show location on map
                    }
                }
                
                Section(header: Text("Icon")) {
                    IconSelectionGrid(selectedIcon: $selectedIcon, availableIcons: availableIcons)
                }
                
                Section(header: Text("Photo")) {
                    if let imageData = waypoint.photoData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(8)
                    }
                    
                    Button("Add Photo") {
                        showImagePicker = true
                    }
                    
                    if waypoint.photoData != nil {
                        Button("Remove Photo") {
                            selectedImage = nil
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Metadata")) {
                    MetadataRow(label: "Created", value: waypoint.createdDate.formatted())
                    MetadataRow(label: "Updated", value: waypoint.lastUpdatedDate.formatted())
                }
            }
            .navigationTitle("Edit Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveWaypoint()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
    
    private func saveWaypoint() {
        var photoData: Data?
        if let image = selectedImage {
            photoData = image.jpegData(compressionQuality: 0.7)
        }
        
        waypointManager.updateWaypoint(
            id: waypoint.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            comments: comments.trimmingCharacters(in: .whitespacesAndNewlines),
            photoData: photoData,
            iconName: selectedIcon
        )
        
        // Update the selected waypoint if it exists
        if let updated = waypointManager.savedWaypoints.first(where: { $0.id == waypoint.id }) {
            selectedWaypoint = updated
        }
    }
}

// MARK: - Supporting Views
struct LocationInfoRow: View {
    let label: String
    let value: Double
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value, specifier: "%.6f")")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

struct IconSelectionGrid: View {
    @Binding var selectedIcon: String
    let availableIcons: [String]
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(availableIcons, id: \.self) { iconName in
                Button(action: {
                    selectedIcon = iconName
                }) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(selectedIcon == iconName ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(selectedIcon == iconName ? Color.blue : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview
struct EditWaypointView_Previews: PreviewProvider {
    static var previews: some View {
        EditWaypointView(
            waypoint: Waypoint(
                coordinate: CLLocationCoordinate2D(latitude: -32.940931, longitude: 151.718029),
                name: "Test Waypoint"
            ),
            waypointManager: WaypointManager(),
            selectedWaypoint: .constant(nil)
        )
    }
}