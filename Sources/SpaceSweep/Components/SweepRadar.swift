import Darwin
import SwiftUI

/// The scanning visual: concentric rings with a rotating sweep. Static when Reduce Motion is on.
struct SweepRadar: View {
    var size: CGFloat = 200
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || !isActive {
                radar(angle: .degrees(35), pulse: 0.5)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    radar(angle: .degrees((t * 120).truncatingRemainder(dividingBy: 360)),
                          pulse: (Darwin.sin(t * 2.2) + 1) / 2)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func radar(angle: Angle, pulse: Double) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                Circle()
                    .strokeBorder(Theme.indigo.opacity(0.18 - Double(index) * 0.03), lineWidth: 1)
                    .padding(CGFloat(index) * size * 0.12)
            }
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Theme.teal.opacity(0.0), location: 0.0),
                            .init(color: Theme.teal.opacity(0.0), location: 0.70),
                            .init(color: Theme.teal.opacity(0.35), location: 0.92),
                            .init(color: Theme.indigo.opacity(0.85), location: 1.0),
                        ]),
                        center: .center
                    )
                )
                .rotationEffect(angle)
                .mask(Circle())
            Circle()
                .fill(RadialGradient(colors: [Theme.indigo.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: size * 0.5))
                .scaleEffect(0.6 + pulse * 0.25)
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: size * 0.26, height: size * 0.26)
                .shadow(color: Theme.indigo.opacity(0.6), radius: 16)
                .overlay(
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: size * 0.11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            // A few "found" blips.
            ForEach(0..<5) { index in
                let blipAngle = Double(index) * 1.37 + 0.6
                let radius = size * (0.22 + 0.05 * Double(index % 3))
                Circle()
                    .fill(Theme.teal)
                    .frame(width: 6, height: 6)
                    .offset(x: CGFloat(Darwin.cos(blipAngle)) * radius, y: CGFloat(Darwin.sin(blipAngle)) * radius)
                    .opacity(0.25 + 0.6 * blipVisibility(blipAngle: blipAngle, sweep: angle))
            }
        }
    }

    /// Blips glow briefly just after the sweep passes them.
    private func blipVisibility(blipAngle: Double, sweep: Angle) -> Double {
        let sweepRadians = sweep.radians.truncatingRemainder(dividingBy: 2 * .pi)
        var delta = sweepRadians - blipAngle.truncatingRemainder(dividingBy: 2 * .pi)
        while delta < 0 { delta += 2 * .pi }
        return max(0, 1 - delta / 1.6)
    }
}
