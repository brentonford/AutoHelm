import SwiftUI

struct CompassView: View {
    let heading: Double
    let bearing: Double?

    private let cardinalDirections: [(String, Double)] = [
        ("N", 0), ("E", 90), ("S", 180), ("W", 270)
    ]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)

            ForEach(cardinalDirections, id: \.0) { direction, angle in
                Text(direction)
                    .font(.caption.bold())
                    .foregroundColor(direction == "N" ? Color.red : .primary)
                    .rotationEffect(.degrees(-heading))
                    .offset(y: -55)
                    .rotationEffect(.degrees(angle))
            }

            ForEach(0..<36, id: \.self) { i in
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 10 : 5)
                    .offset(y: -65)
                    .rotationEffect(.degrees(Double(i) * 10))
            }

            if let bearing {
                BearingIndicator()
                    .rotationEffect(.degrees(bearing - heading))
            }

            HeadingIndicator()
        }
        .rotationEffect(.degrees(heading))
    }
}

struct HeadingIndicator: View {
    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.red)
                .frame(width: 16, height: 20)
            Rectangle()
                .fill(Color.red)
                .frame(width: 4, height: 35)
        }
        .offset(y: -25)
    }
}

struct BearingIndicator: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 12, height: 12)
            .offset(y: -45)
    }
}

struct Triangle: Shape {
    nonisolated func path(in rect: CGRect) -> SwiftUI.Path {
        var path = SwiftUI.Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct HoldButton: View {
    var label: String?
    var systemImage: String?
    var isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)

            if let label {
                Text(label)
                    .font(.title2.bold())
                    .foregroundColor(isActive ? Color.blue : .primary)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(isActive ? Color.blue : .primary)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isActive {
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isActive {
                        onRelease()
                    }
                }
        )
        .accessibilityLabel(label ?? systemImage ?? "Button")
    }
}

struct MomentaryButton: View {
    var label: String?
    var systemImage: String?
    var isActive: Bool
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)

                if let label {
                    Text(label)
                        .font(.title2.bold())
                        .foregroundColor(isActive ? Color.blue : .primary)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(isActive ? Color.blue : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? systemImage ?? "Button")
    }
}