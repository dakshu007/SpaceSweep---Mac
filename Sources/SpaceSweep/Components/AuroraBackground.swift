import SwiftUI

/// Soft, slowly drifting colour fields behind the content. Static when Reduce Motion is on.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let strength = colorScheme == .dark ? 0.22 : 0.12
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Circle()
                    .fill(Theme.teal.opacity(strength))
                    .frame(width: size.width * 0.7)
                    .offset(x: drift ? -size.width * 0.28 : -size.width * 0.18, y: drift ? -size.height * 0.30 : -size.height * 0.22)
                Circle()
                    .fill(Theme.indigo.opacity(strength))
                    .frame(width: size.width * 0.6)
                    .offset(x: drift ? size.width * 0.30 : size.width * 0.22, y: drift ? -size.height * 0.05 : -size.height * 0.16)
                Circle()
                    .fill(Theme.violet.opacity(strength * 0.8))
                    .frame(width: size.width * 0.55)
                    .offset(x: drift ? size.width * 0.05 : -size.width * 0.05, y: drift ? size.height * 0.42 : size.height * 0.34)
            }
            .blur(radius: 90)
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
