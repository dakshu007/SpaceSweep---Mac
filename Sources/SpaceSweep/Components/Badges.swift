import SwiftUI
import SpaceSweepCore

struct SafetyBadge: View {
    let tier: SafetyTier
    var compact = false

    var body: some View {
        let color = Theme.color(for: tier)
        HStack(spacing: 4) {
            Image(systemName: Theme.symbol(for: tier))
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            if !compact {
                Text(tier.title)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tier.title) tier")
    }
}

/// Small rounded-square tile with a gradient and a white SF Symbol.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.gradient(for: color))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.35), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// A coloured status capsule for things like "Xcode is running".
struct StatusChip: View {
    let text: String
    let symbol: String
    var color: Color = Theme.sun

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Tri-state checkbox for selecting a whole rule group.
struct TriStateCheckbox: View {
    enum CheckState { case off, mixed, on }
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(state == .off ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accent))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select")
        .accessibilityValue(state == .on ? "Selected" : (state == .mixed ? "Partly selected" : "Not selected"))
    }

    private var symbol: String {
        switch state {
        case .off: return "circle"
        case .mixed: return "minus.circle.fill"
        case .on: return "checkmark.circle.fill"
        }
    }
}

struct StatTile: View {
    let title: String
    let value: Int64
    let caption: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(color.opacity(0.15)))
                Spacer()
            }
            Text(Format.bytes(value))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}
