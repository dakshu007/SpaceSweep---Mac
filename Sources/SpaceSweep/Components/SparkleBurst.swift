import Darwin
import SwiftUI

/// A brief, celebratory burst of sparkles. Not shown when Reduce Motion is on.
struct SparkleBurst: View {
    var trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private let particles: [(angle: Double, distance: CGFloat, size: CGFloat, color: Color)] = (0..<18).map { index in
        let colors = [Theme.teal, Theme.indigo, Theme.violet, Theme.mint]
        return (Double(index) / 18 * 2 * .pi + Double(index % 3) * 0.2,
                CGFloat(70 + (index * 37) % 60),
                CGFloat(5 + index % 4 * 2),
                colors[index % colors.count])
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(particles.indices, id: \.self) { index in
                    let particle = particles[index]
                    Image(systemName: index % 3 == 0 ? "sparkle" : "circle.fill")
                        .font(.system(size: particle.size * (index % 3 == 0 ? 2.2 : 1)))
                        .foregroundStyle(particle.color)
                        .offset(x: expanded ? CGFloat(Darwin.cos(particle.angle)) * particle.distance : 0,
                                y: expanded ? CGFloat(Darwin.sin(particle.angle)) * particle.distance : 0)
                        .scaleEffect(expanded ? 0.4 : 1)
                        .opacity(expanded ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if trigger { fire() } }
        .onChange(of: trigger) { _, newValue in if newValue { fire() } }
    }

    private func fire() {
        guard !reduceMotion else { return }
        expanded = false
        withAnimation(.easeOut(duration: 1.1)) { expanded = true }
    }
}
