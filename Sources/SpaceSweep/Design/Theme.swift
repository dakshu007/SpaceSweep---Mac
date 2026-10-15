import SwiftUI
import SpaceSweepCore

/// SpaceSweep's visual language: native materials, one brand gradient, restrained tier colours.
enum Theme {
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.98)
    static let teal = Color(red: 0.15, green: 0.78, blue: 0.85)
    static let violet = Color(red: 0.63, green: 0.38, blue: 0.97)
    static let mint = Color(red: 0.20, green: 0.78, blue: 0.52)
    static let amber = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let slate = Color(red: 0.47, green: 0.53, blue: 0.66)
    static let sun = Color(red: 0.96, green: 0.76, blue: 0.18)

    static let accent = indigo

    static let brandGradient = LinearGradient(colors: [teal, indigo, violet],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ringGradient = AngularGradient(colors: [teal, indigo, violet, teal], center: .center)

    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 14

    static func color(for tier: SafetyTier) -> Color {
        switch tier {
        case .safe: return mint
        case .review: return amber
        case .protected: return slate
        case .blocked: return sun
        }
    }

    static func symbol(for tier: SafetyTier) -> String {
        switch tier {
        case .safe: return "checkmark.shield.fill"
        case .review: return "eye.fill"
        case .protected: return "lock.fill"
        case .blocked: return "pause.circle.fill"
        }
    }

    static func color(for category: RuleCategory) -> Color {
        switch category {
        case .xcode: return Color(red: 0.25, green: 0.56, blue: 1.0)
        case .simulator: return Color(red: 0.36, green: 0.80, blue: 0.98)
        case .packageManager: return Color(red: 0.92, green: 0.36, blue: 0.48)
        case .browser: return Color(red: 0.98, green: 0.62, blue: 0.20)
        case .appCache: return Color(red: 0.62, green: 0.44, blue: 0.98)
        case .logs: return Color(red: 0.55, green: 0.62, blue: 0.70)
        case .trash: return Color(red: 0.45, green: 0.48, blue: 0.55)
        case .backups: return Color(red: 0.20, green: 0.75, blue: 0.62)
        }
    }

    static func gradient(for color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.70)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    func card(padding: CGFloat = 20, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: LinearGradient = Theme.brandGradient
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, tint: tint, large: large, isEnabled: isEnabled)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: LinearGradient
        let large: Bool
        let isEnabled: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 26 : 18)
                .padding(.vertical, large ? 13 : 9)
                .background {
                    Capsule(style: .continuous)
                        .fill(tint)
                        .overlay(Capsule(style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0)))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: Theme.indigo.opacity(isEnabled ? (hovering ? 0.55 : 0.35) : 0), radius: hovering ? 18 : 12, y: 6)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1)))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: hovering)
                .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, large: large)
    }

    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(large ? .title3.weight(.medium) : .body.weight(.medium))
                .padding(.horizontal, large ? 22 : 16)
                .padding(.vertical, large ? 13 : 9)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.10 : 0.06)))
                }
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryLarge: PrimaryButtonStyle { PrimaryButtonStyle(large: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondaryLarge: SecondaryButtonStyle { SecondaryButtonStyle(large: true) }
}

/// A borderless icon button with a soft hover highlight.
struct GhostIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .padding(6)
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.08 : 0))))
                .onHover { hovering = $0 }
                .contentShape(Circle())
        }
    }
}
