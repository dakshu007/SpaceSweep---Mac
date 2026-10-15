import SpaceSweepCore
import SwiftUI

/// Developer-focused view of the same scan: one card per tool, live app state, quick include toggles.
struct DeveloperCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var detailRule: CleanupRule?

    private var rules: [CleanupRule] { model.registry.developerRules }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                    ForEach(rules) { rule in
                        ToolCard(rule: rule, result: model.report?.result(for: rule.id)) { detailRule = rule }
                    }
                }
                tips
            }
            .padding(28)
            .padding(.bottom, model.report == nil ? 0 : 90)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if model.report != nil { SelectionBar() }
        }
        .sheet(item: $detailRule) { rule in
            RuleDetailSheet(rule: rule, result: model.report?.result(for: rule.id))
                .environment(model)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            IconTile(symbol: "hammer.fill", color: Theme.indigo, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer caches").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Build products and package caches that pile up while you build apps and websites. Your projects, node_modules folders and Git data are never touched.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.report == nil {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan Mac", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.primary)
                .disabled(model.isScanning || model.isCleaning)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.bytes(developerBytes)).font(.title2.weight(.bold)).monospacedDigit()
                    Text("found in developer caches").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 22, radius: 24)
    }

    private var developerBytes: Int64 {
        guard let report = model.report else { return 0 }
        return rules.compactMap { report.result(for: $0.id) }
            .flatMap(\.candidates)
            .filter { $0.tier != .protected }
            .reduce(0) { $0.saturatingAdd($1.estimatedBytes) }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Also worth knowing").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                tip(symbol: "folder.badge.minus", title: "Old node_modules",
                    text: "SpaceSweep never deletes inside your projects. Remove node_modules from projects you’ve finished with yourself — `npm install` restores them.")
                tip(symbol: "shippingbox.circle", title: "Docker Desktop",
                    text: "Images and volumes live in Docker’s disk image. Reclaim space with Docker Desktop › Troubleshoot or `docker system prune`.")
                tip(symbol: "iphone.gen3", title: "Simulator runtimes",
                    text: "Manage installed runtimes in Xcode › Settings › Platforms. Unavailable simulators: `xcrun simctl delete unavailable`.")
            }
        }
    }

    private func tip(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.brandGradient).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 14, radius: Theme.rowRadius)
    }
}

private struct ToolCard: View {
    @Environment(AppModel.self) private var model
    let rule: CleanupRule
    let result: RuleScanResult?
    let showDetail: () -> Void
    @State private var hovering = false

    private var color: Color { Theme.color(for: rule.category) }
    private var bytes: Int64 { result?.totalBytes ?? 0 }
    private var selectableIDs: [UUID] { result?.candidates.filter(\.isSelectable).map(\.id) ?? [] }
    private var isIncluded: Bool { !selectableIDs.isEmpty && selectableIDs.allSatisfy { model.selection.contains($0) } }
    private var runningBlockers: [KnownApp] { rule.requiresClosedApps.filter { model.isRunning($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                IconTile(symbol: rule.symbolName, color: color, size: 42)
                Spacer()
                SafetyBadge(tier: rule.tier)
                Button(action: showDetail) { Image(systemName: "info.circle") }
                    .buttonStyle(GhostIconButtonStyle())
                    .help("Why is this here?")
                    .accessibilityLabel("Details for \(rule.title)")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title).font(.headline)
                Text(rule.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            HStack(alignment: .lastTextBaseline) {
                sizeView
                Spacer()
                if !selectableIDs.isEmpty {
                    Toggle(isOn: Binding(get: { isIncluded }, set: { include in
                        if include { model.selection.formUnion(selectableIDs) } else { model.selection.subtract(selectableIDs) }
                    })) {
                        Text("Include").font(.callout)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Include \(rule.title)")
                }
            }
            statusLine
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(color.opacity(hovering ? 0.22 : 0.12)).frame(width: 150, height: 150).blur(radius: 40).offset(x: 50, y: -60)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isIncluded ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.07), lineWidth: isIncluded ? 1.5 : 1)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .animation(.snappy, value: isIncluded)
    }

    @ViewBuilder
    private var sizeView: some View {
        if let result {
            switch result.status {
            case .scanned:
                VStack(alignment: .leading, spacing: 0) {
                    Text(result.candidates.isEmpty ? "Empty" : Format.bytes(bytes))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(Format.count(result.candidates.count, "item")).font(.caption).foregroundStyle(.secondary)
                }
            case .notFound:
                Text("Not found").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
            case .disabled:
                Text("Turned off").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
            case .permissionDenied, .rootRejected:
                Text("Unavailable").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
        } else {
            Text(model.isScanning ? "Scanning…" : "Not scanned").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !runningBlockers.isEmpty {
            StatusChip(text: ScannerService.quitMessage(for: runningBlockers), symbol: "pause.circle.fill")
        } else if let result, !result.blockingApps.isEmpty {
            StatusChip(text: "Closed since scan — rescan to include", symbol: "arrow.clockwise", color: Theme.teal)
        } else if let message = result?.status.message, result?.status != .notFound {
            StatusChip(text: message, symbol: "info.circle", color: Theme.slate)
                .lineLimit(1)
        } else if rule.tier == .safe {
            StatusChip(text: "Selected automatically when found", symbol: "checkmark.shield", color: Theme.mint)
        } else if rule.tier == .review {
            StatusChip(text: "Review before cleaning", symbol: "eye", color: Theme.amber)
        } else {
            StatusChip(text: "Display only", symbol: "lock", color: Theme.slate)
        }
    }
}
