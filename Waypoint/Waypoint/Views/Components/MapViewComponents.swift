import SwiftUI
import MapKit
import CoreLocation

struct QuickSpotLockButton: View {
    let canNavigate: Bool
    let isDisengaging: Bool
    let onEngage: () -> Void
    
    @State private var showingInitWarning = false
    
    var body: some View {
        Button {
            showingInitWarning = true
        } label: {
            HStack {
                if isDisengaging {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Disengaging...")
                } else {
                    Image(systemName: "pin.circle.fill")
                    Text("Engage Spot Lock Here")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(isDisengaging ? .orange : .blue)
        .disabled(!canNavigate || isDisengaging)
        .alert("Motor Initialization Required", isPresented: $showingInitWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") {
                onEngage()
            }
        } message: {
            Text("Before engaging Spot Lock, ensure the electric motor is:\n\n• Motor is ON\n• Speed is set to 0\n\nSpot Lock will only control speed levels.")
        }
    }
}