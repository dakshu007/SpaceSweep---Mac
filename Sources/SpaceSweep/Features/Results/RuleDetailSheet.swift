import SpaceSweepCore
import SwiftUI

/// "Why is this here?" — the full story for one rule, including the exact location and the effect of cleaning.
struct RuleDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: CleanupRule
    let result: RuleScanResult?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                IconTile(symbol: rule.symbolName, color: Theme.color(for: rule.category), size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.title).font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        SafetyBadge(tier: rule.tier)
                        Text(rule.category.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let result, result.status == .scanned {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.bytes(result.totalBytes)).font(.title2.weight(.bold)).monospacedDigit()
                        Text(Format.count(result.candidates.count, "item")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Why is this here?", symbol: "questionmark.circle", text: rule.explanation)
                    section(rule.isDeletable ? "What happens if it’s cleaned" : "How to manage it",
                            symbol: rule.isDeletable ? "arrow.triangle.2.circlepath" : "hand.raised",
                            text: rule.isDeletable ? rule.consequence : (rule.managementHint ?? rule.consequence))
                    if rule.isDeletable {
                        section("What SpaceSweep removes", symbol: "scissors",
                                text: rule.minimumAgeDays.map { "Only items inside the folder below that were last modified more than \($0) days ago. The folder itself always stays." }
                                    ?? "Only the items inside the folder below — never the folder itself. Symbolic links are skipped, and every item is checked again right before removal.")
                    }
                    if !rule.requiresClosedApps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Needs these apps closed", symbol: "app.badge.checkmark")
                            HStack(spacing: 8) {
                                ForEach(rule.requiresClosedApps, id: \.bundleIdentifier) { app in
                                    StatusChip(text: model.isRunning(app) ? "\(app.displayName) is running" : "\(app.displayName) is closed",
                                               symbol: model.isRunning(app) ? "pause.circle.fill" : "checkmark.circle.fill",
                                               color: model.isRunning(app) ? Theme.sun : Theme.mint)
                                }
                            }
                        }
                    }
                    if let message = result?.status.message {
                        section("Status", symbol: "info.circle", text: message)
                    }
                    if let result, result.skippedSymbolicLinks > 0 || result.skippedOverlaps > 0 || result.unreadableItems > 0 {
                        section("Skipped during scan", symbol: "arrow.uturn.right",
                                text: skippedText(result))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        label("Location", symbol: "folder")
                        Text(rule.displayRoot)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                if model.rootExists(rule) {
                    Button {
                        model.revealRoot(of: rule)
                    } label: {
                        Label("Show Folder in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 560, height: 600)
    }

    private func label(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func section(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title, symbol: symbol)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func skippedText(_ result: RuleScanResult) -> String {
        var parts: [String] = []
        if result.skippedSymbolicLinks > 0 { parts.append("\(Format.count(result.skippedSymbolicLinks, "symbolic link")) (never followed)") }
        if result.skippedOverlaps > 0 { parts.append("\(Format.count(result.skippedOverlaps, "folder")) covered by a more specific rule") }
        if result.unreadableItems > 0 { parts.append("\(Format.count(result.unreadableItems, "unreadable item")) (sizes are minimums)") }
        return parts.joined(separator: " · ")
    }
}
