import Darwin
import SwiftUI

/// A large ring showing used capacity with a gradient sweep and soft glow.
struct StorageRing<Center: View>: View {
    let usedFraction: Double
    var lineWidth: CGFloat = 22
    @ViewBuilder var center: () -> Center

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, shown))
                .stroke(Theme.ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.indigo.opacity(0.45), radius: 14)
            // Bright cap riding the end of the arc.
            RingCap(fraction: shown, capSize: lineWidth * 0.36)
                .fill(.white.opacity(0.9))
                .opacity(shown > 0.02 ? 1 : 0)
            center()
                .padding(lineWidth + 8)
        }
        .padding(lineWidth / 2)
        .onAppear { animate(to: usedFraction) }
        .onChange(of: usedFraction) { _, newValue in animate(to: newValue) }
    }

    private func animate(to value: Double) {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.85)) { shown = value }
        }
    }
}

private struct RingCap: Shape {
    var fraction: Double
    let capSize: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let angle: Double = fraction * 2 * Double.pi - Double.pi / 2
        let center = CGPoint(x: rect.midX + radius * CGFloat(Darwin.cos(angle)),
                             y: rect.midY + radius * CGFloat(Darwin.sin(angle)))
        return Path(ellipseIn: CGRect(x: center.x - capSize / 2, y: center.y - capSize / 2, width: capSize, height: capSize))
    }
}

/// Horizontal used / available bar with legend.
struct CapacityBar: View {
    let usedBytes: Int64
    let availableBytes: Int64
    let totalBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let fraction = totalBytes > 0 ? min(1, max(0, Double(usedBytes) / Double(totalBytes))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Theme.brandGradient)
                        .frame(width: max(8, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
            HStack(spacing: 16) {
                legend(color: Theme.indigo, title: "Used", value: Format.bytes(usedBytes))
                legend(color: Color.primary.opacity(0.18), title: "Available", value: Format.bytes(availableBytes))
                Spacer()
                Text("\(Format.bytes(totalBytes)) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage")
        .accessibilityValue("\(Format.bytes(usedBytes)) used, \(Format.bytes(availableBytes)) available of \(Format.bytes(totalBytes))")
    }

    private func legend(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.caption)
    }
}
