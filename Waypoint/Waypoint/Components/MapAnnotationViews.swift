import SwiftUI
import MapKit

// MARK: - Saved Waypoint Annotation View
struct SavedWaypointAnnotationView: View {
    let waypoint: Waypoint
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: waypoint.iconName)
                .font(.system(size: 16))
                .foregroundColor(.yellow)
                .background(Color.white)
                .clipShape(Circle())
            Text(waypoint.name)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.8))
                .cornerRadius(4)
        }
    }
}

// MARK: - Search Result Annotation View
struct SearchResultAnnotationView: View {
    let item: MKMapItem
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .background(Color.white)
                .clipShape(Circle())
            Text(item.name ?? "")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(4)
        }
    }
}

// MARK: - Selected Waypoint Annotation View
struct SelectedWaypointAnnotationView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.red)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundColor(.red)
                .offset(y: -4)
        }
    }
}

// MARK: - Active Target Annotation View
struct ActiveTargetAnnotationView: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 32, height: 32)
                Image(systemName: "target")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            Text("Active Target")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .cornerRadius(4)
        }
    }
}

// MARK: - Offline Region Annotation View
struct OfflineRegionAnnotationView: View {
    let region: DownloadedRegion
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
                .background(Color.white)
                .clipShape(Circle())
            Text(region.name)
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green)
                .cornerRadius(4)
        }
    }
}