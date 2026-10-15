import SwiftUI
import SpaceSweepCore

/// Stacked bar of what SpaceSweep found, by category. This is SpaceSweep's own scan result —
/// not a replica of macOS's Storage categories.
struct CategoryBar: View {
    let segments: [(category: RuleCategory, bytes: Int64)]
    @State private var hovered: RuleCategory?

    private var total: Int64 { segments.reduce(0) { $0.saturatingAdd($1.bytes) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(segments, id: \.category) { segment in
                        let fraction = total > 0 ? Double(segment.bytes) / Double(total) : 0
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.gradient(for: Theme.color(for: segment.category)))
                            .frame(width: max(6, (proxy.size.width - CGFloat(segments.count - 1) * 3) * fraction))
                            .opacity(hovered == nil || hovered == segment.category ? 1 : 0.35)
                            .onHover { hovered = $0 ? segment.category : nil }
                            .help("\(segment.category.title): \(Format.bytes(segment.bytes))")
                    }
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.2), value: hovered)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(segments, id: \.category) { segment in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.color(for: segment.category)).frame(width: 10, height: 10)
                        Text(segment.category.title).font(.callout)
                        Spacer(minLength: 4)
                        Text(Format.bytes(segment.bytes)).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 12)
                    .opacity(hovered == nil || hovered == segment.category ? 1 : 0.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SpaceSweep scan results by category")
        .accessibilityValue(segments.map { "\($0.category.title) \(Format.bytes($0.bytes))" }.joined(separator: ", "))
    }
}
