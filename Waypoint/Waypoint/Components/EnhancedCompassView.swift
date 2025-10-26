import SwiftUI

// MARK: - Enhanced Compass View
struct EnhancedCompassView: View {
    let heading: Float
    let bearing: Float
    let size: CGFloat
    
    init(heading: Float, bearing: Float, size: CGFloat = 80) {
        self.heading = heading
        self.bearing = bearing
        self.size = size
    }
    
    var body: some View {
        ZStack {
            CompassRing(size: size)
            CompassNeedle(heading: heading, size: size)
            BearingIndicator(bearing: bearing, heading: heading, size: size)
            CompassCenter(size: size)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Compass Components
struct CompassRing: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            ForEach(0..<12) { index in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: index % 3 == 0 ? 2 : 1, height: index % 3 == 0 ? 8 : 4)
                    .offset(y: -size/2 + 6)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
            
            // Cardinal direction labels
            ForEach([("N", 0), ("E", 90), ("S", 180), ("W", 270)], id: \.0) { label, angle in
                Text(label)
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundColor(.primary)
                    .offset(y: -size/2 + size * 0.15)
                    .rotationEffect(.degrees(Double(angle)))
            }
        }
    }
}

struct CompassNeedle: View {
    let heading: Float
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // North needle (red)
            Path { path in
                path.move(to: CGPoint(x: 0, y: -size/2 + 10))
                path.addLine(to: CGPoint(x: -3, y: 0))
                path.addLine(to: CGPoint(x: 3, y: 0))
                path.closeSubpath()
            }
            .fill(Color.red)
            
            // South needle (white with black outline)
            Path { path in
                path.move(to: CGPoint(x: 0, y: size/2 - 10))
                path.addLine(to: CGPoint(x: -3, y: 0))
                path.addLine(to: CGPoint(x: 3, y: 0))
                path.closeSubpath()
            }
            .fill(Color.white)
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size/2 - 10))
                    path.addLine(to: CGPoint(x: -3, y: 0))
                    path.addLine(to: CGPoint(x: 3, y: 0))
                    path.closeSubpath()
                }
                .stroke(Color.black, lineWidth: 1)
            )
        }
        .rotationEffect(.degrees(Double(-heading)))
        .animation(.easeOut(duration: 0.3), value: heading)
    }
}

struct BearingIndicator: View {
    let bearing: Float
    let heading: Float
    let size: CGFloat
    
    private var relativeBearing: Double {
        let relative = Double(bearing - heading)
        return relative < 0 ? relative + 360 : relative
    }
    
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .offset(y: -size/2 + 15)
            .rotationEffect(.degrees(relativeBearing))
            .animation(.easeOut(duration: 0.3), value: relativeBearing)
    }
}

struct CompassCenter: View {
    let size: CGFloat
    
    var body: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 4, height: 4)
    }
}

// MARK: - Preview
struct EnhancedCompassView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            EnhancedCompassView(heading: 45, bearing: 120, size: 100)
            EnhancedCompassView(heading: 180, bearing: 270, size: 80)
            EnhancedCompassView(heading: 315, bearing: 45, size: 60)
        }
        .padding()
    }
}