import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var mapType: MKMapType = .standard
    @State private var isLoadingSatellite: Bool = false
    
    var body: some View {
        ZStack {
            Map(position: $position) {
                if locationManager.userLocation != nil {
                    UserAnnotation()
                }
            }
            .mapStyle(currentMapStyle)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                requestLocationPermission()
            }
            .onChange(of: locationManager.userLocation) { oldValue, newValue in
                if let location = newValue {
                    updateMapPosition(to: location)
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: toggleMapType) {
                        ZStack {
                            if isLoadingSatellite {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: mapType == .standard ? "map" : "globe")
                                    .foregroundColor(.primary)
                                    .font(.title2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                    }
                    .disabled(isLoadingSatellite)
                    .padding(.trailing)
                }
                .padding(.top, 60)
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Button(action: centerOnUserLocation) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.primary)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing)
                }
                .padding(.bottom, 100)
            }
        }
    }
    
    private var currentMapStyle: MapStyle {
        switch mapType {
        case .standard:
            return .standard
        case .satellite:
            return .imagery(elevation: .flat)
        default:
            return .standard
        }
    }
    
    private func requestLocationPermission() {
        locationManager.requestPermission()
    }
    
    private func updateMapPosition(to location: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 1.0)) {
            position = .region(MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
    
    private func toggleMapType() {
        if mapType == .standard {
            isLoadingSatellite = true
            mapType = .satellite
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isLoadingSatellite = false
            }
        } else {
            mapType = .standard
        }
    }
    
    private func centerOnUserLocation() {
        guard let location = locationManager.userLocation else { return }
        updateMapPosition(to: location)
    }
}

#Preview {
    MapView()
}