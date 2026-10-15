import SpaceSweepCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var detailRule: CleanupRule?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case safe = "Safe"
        case review = "Review"
        case unavailable = "Unavailable"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let report = model.report {
                content(report)
            } else {
                EmptyStateView(symbol: "sparkle.magnifyingglass", title: "No scan results yet",
                               message: model.lastCleanup != nil
                                   ? "Results are cleared after each cleanup so you never act on outdated information. Scan again to see what’s left."
                                   : "Scan your Mac to find known caches and build data. Nothing is removed until you review and confirm.") {
                    Button {
                        model.startScan()
                    } label: {
                        Label("Scan Mac", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.primaryLarge)
                    .disabled(model.isScanning || model.isCleaning)
                }
            }
        }
        .sheet(item: $detailRule) { rule in
            RuleDetailSheet(rule: rule, result: model.report?.result(for: rule.id))
                .environment(model)
        }
    }

    // MARK: Content

    private func content(_ report: ScanReport) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                header(report)
                if model.reportIsStale {
                    banner(symbol: "clock.badge.exclamationmark", color: Theme.amber,
                           text: "These results are more than 10 minutes old. Rescan before cleaning so SpaceSweep acts on current data.",
                           action: ("Rescan", { model.startScan() }))
                }
                if case .fullDiskAccessWouldHelp(let titles) = PermissionState.from(report: report) {
                    banner(symbol: "lock.shield", color: Theme.indigo,
                           text: "\(titles.joined(separator: ", ")) couldn’t be read because of macOS privacy protections. This is optional — grant Full Disk Access only if you want SpaceSweep to measure these.",
                           action: ("Open Settings", { model.openFullDiskAccessSettings() }))
                }

                ForEach(sections(report), id: \.tier) { section in
                    sectionHeader(section)
                    ForEach(section.results) { result in
                        RuleGroupCard(result: result, tierOverride: section.tier,
                                      isExpanded: Binding(
                                        get: { expanded.contains(sectionKey(section.tier, result.rule.id)) },
                                        set: { open in
                                            let key = sectionKey(section.tier, result.rule.id)
                                            if open { expanded.insert(key) } else { expanded.remove(key) }
                                        }),
                                      search: search,
                                      showDetail: { detailRule = result.rule })
                    }
                }

                if filter == .all || filter == .unavailable {
                    unavailableRules(report)
                    ManagedByMacOSCard()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 110)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter results")
        .safeAreaInset(edge: .bottom) { SelectionBar() }
    }

    private func header(_ report: ScanReport) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanned \(Format.relative(report.finishedAt, now: model.clock))")
                    .font(.title2.weight(.semibold))
                Text("\(Format.count(report.allCandidates.count, "item")) in \(Format.count(report.ruleResults.filter { !$0.candidates.isEmpty }.count, "category", "categories"))\(report.isPartial ? " · some locations couldn’t be read" : "")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)
        }
    }

    private func banner(symbol: String, color: Color, text: String, action: (String, () -> Void)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action.0, action: action.1).buttonStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: Sections

    struct TierSection {
        let tier: SafetyTier
        let results: [RuleScanResult]
        var bytes: Int64 { results.reduce(0) { $0.saturatingAdd($1.bytes(in: tier)) } }
    }

    private func sections(_ report: ScanReport) -> [TierSection] {
        let tiers: [SafetyTier]
        switch filter {
        case .all: tiers = [.safe, .review, .blocked, .protected]
        case .safe: tiers = [.safe]
        case .review: tiers = [.review]
        case .unavailable: tiers = [.blocked, .protected]
        }
        return tiers.compactMap { tier in
            let results = report.ruleResults.filter { result in
                result.candidates.contains { $0.tier == tier && matches($0, rule: result.rule) }
            }
            .sorted { $0.bytes(in: tier) > $1.bytes(in: tier) }
            return results.isEmpty ? nil : TierSection(tier: tier, results: results)
        }
    }

    private func matches(_ candidate: CleanupCandidate, rule: CleanupRule) -> Bool {
        guard !search.isEmpty else { return true }
        return candidate.displayName.localizedCaseInsensitiveContains(search)
            || rule.title.localizedCaseInsensitiveContains(search)
            || candidate.displayPath.localizedCaseInsensitiveContains(search)
    }

    private func sectionKey(_ tier: SafetyTier, _ ruleID: String) -> String { "\(tier.rawValue)/\(ruleID)" }

    private func sectionHeader(_ section: TierSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Theme.symbol(for: section.tier))
                .foregroundStyle(Theme.color(for: section.tier))
            Text(section.tier.sectionTitle)
                .font(.headline)
            Text(sectionSubtitle(section.tier))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.bytes(section.bytes))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionSubtitle(_ tier: SafetyTier) -> String {
        switch tier {
        case .safe: return "Known, rebuildable data · selected by default"
        case .review: return "May matter to you · never selected automatically"
        case .blocked: return "Can’t be cleaned right now"
        case .protected: return "Shown for context · never cleaned"
        }
    }

    @ViewBuilder
    private func unavailableRules(_ report: ScanReport) -> some View {
        let problems = report.ruleResults.filter { $0.status.isProblem }
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.folder").foregroundStyle(Theme.slate)
                    Text("Couldn’t inspect").font(.headline)
                    Text("Not counted as junk").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 12)
                ForEach(problems) { result in
                    HStack(spacing: 12) {
                        IconTile(symbol: result.rule.symbolName, color: Theme.slate, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.rule.title).font(.callout.weight(.semibold))
                            Text(result.status.message ?? "").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if case .permissionDenied(true) = result.status {
                            Button("Full Disk Access…") { model.openFullDiskAccessSettings() }
                                .buttonStyle(.secondary)
                        }
                        Button {
                            detailRule = result.rule
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(GhostIconButtonStyle())
                        .help("About this location")
                    }
                    .card(padding: 14, radius: Theme.rowRadius)
                }
            }
        }
    }
}

// MARK: - Rule group

struct RuleGroupCard: View {
    @Environment(AppModel.self) private var model
    let result: RuleScanResult
    let tierOverride: SafetyTier
    @Binding var isExpanded: Bool
    let search: String
    let showDetail: () -> Void
    @State private var hovering = false

    private var candidates: [CleanupCandidate] {
        result.candidates.filter { candidate in
            candidate.tier == tierOverride && (search.isEmpty
                || candidate.displayName.localizedCaseInsensitiveContains(search)
                || result.rule.title.localizedCaseInsensitiveContains(search)
                || candidate.displayPath.localizedCaseInsensitiveContains(search))
        }
    }

    private var bytes: Int64 { candidates.reduce(0) { $0.saturatingAdd($1.estimatedBytes) } }
    private var selectable: Bool { candidates.contains(where: \.isSelectable) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(candidates.prefix(200)) { candidate in
                        CandidateRow(candidate: candidate)
                        if candidate.id != candidates.prefix(200).last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                    if candidates.count > 200 {
                        Text("Showing the 200 largest of \(candidates.count) items.")
                            .font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(hovering ? Theme.color(for: tierOverride).opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.25), value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if selectable {
                TriStateCheckbox(state: groupState) { toggleGroup() }
                    .help("Select every item in this group")
            } else {
                Image(systemName: Theme.symbol(for: tierOverride))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.color(for: tierOverride))
                    .frame(width: 20)
            }
            IconTile(symbol: result.rule.symbolName, color: Theme.color(for: result.rule.category))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(result.rule.title).font(.body.weight(.semibold))
                    SafetyBadge(tier: tierOverride)
                    if result.rule.removesUserFilesPermanently {
                        StatusChip(text: "Permanent", symbol: "exclamationmark.triangle", color: Theme.amber)
                    }
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(bytes))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(Format.count(candidates.count, "item"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(action: showDetail) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(GhostIconButtonStyle())
            .help("Why is this here?")
            .accessibilityLabel("Details for \(result.rule.title)")
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(GhostIconButtonStyle())
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    private var statusLine: String {
        if tierOverride == .blocked, !result.blockingApps.isEmpty {
            let stillRunning = result.blockingApps.filter { model.isRunning($0) }
            return stillRunning.isEmpty
                ? "\(result.blockingApps.map(\.displayName).joined(separator: " and ")) has quit — rescan to include these."
                : ScannerService.quitMessage(for: stillRunning)
        }
        return result.rule.summary
    }

    private var groupState: TriStateCheckbox.CheckState {
        let ids = candidates.filter(\.isSelectable).map(\.id)
        let count = ids.filter { model.selection.contains($0) }.count
        if count == 0 { return .off }
        return count == ids.count ? .on : .mixed
    }

    private func toggleGroup() {
        let ids = candidates.filter(\.isSelectable).map(\.id)
        if groupState == .on {
            model.selection.subtract(ids)
        } else {
            model.selection.formUnion(ids)
        }
    }
}

struct CandidateRow: View {
    @Environment(AppModel.self) private var model
    let candidate: CleanupCandidate

    var body: some View {
        HStack(spacing: 12) {
            if candidate.isSelectable {
                Toggle(isOn: Binding(
                    get: { model.selection.contains(candidate.id) },
                    set: { _ in model.toggle(candidate) }
                )) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Select \(candidate.displayName)")
                    .frame(width: 26)
            } else {
                Image(systemName: Theme.symbol(for: candidate.tier))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.color(for: candidate.tier))
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(candidate.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let reason = candidate.blockedReason {
                    Label(reason, systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }
            }
            Spacer(minLength: 8)
            if let modified = candidate.modifiedAt {
                Text(modified.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Last modified")
            }
            Text(candidate.itemCount > 0 ? Format.count(candidate.itemCount, "file") : "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text((candidate.sizeIsPartial ? "≥ " : "") + Format.bytes(candidate.estimatedBytes))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
                .help(candidate.sizeIsPartial ? "Some files couldn’t be read, so this is a minimum." : "Approximate allocated size")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(candidate) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Selection bar

struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 40, height: 40)
                Image(systemName: "wand.and.stars").foregroundStyle(.white).font(.system(size: 17, weight: .semibold))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selection.isEmpty ? "Nothing selected" : "≈ \(Format.bytes(model.selectedBytes)) selected")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.selectedBytes)))
                    .animation(.snappy, value: model.selectedBytes)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Safe Defaults") { model.resetSelectionToSafeDefaults() }
                .buttonStyle(.secondary)
                .help("Select only Safe items")
            if model.reportIsStale {
                Button {
                    model.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.primary)
            } else {
                Button {
                    model.beginCleanup()
                } label: {
                    Label("Clean Selected…", systemImage: "sparkles")
                }
                .buttonStyle(.primary)
                .disabled(model.selectedCandidates.isEmpty || model.isCleaning)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: 1100)
    }

    private var detail: String {
        let count = model.selectedCandidates.count
        var parts = [Format.count(count, "item")]
        if model.selectionIncludesReview { parts.append("includes Review items") }
        parts.append("you’ll confirm before anything is removed")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Managed by macOS

struct ManagedByMacOSCard: View {
    private let items: [(symbol: String, title: String, text: String)] = [
        ("clock.arrow.circlepath", "Time Machine local snapshots",
         "Managed by macOS and counted as available space. macOS removes them automatically when space is needed."),
        ("memorychip", "Swap and sleep image",
         "Virtual-memory files in /private/var/vm. Managed by macOS; restart to reset."),
        ("applelogo", "macOS and system files",
         "Protected by System Integrity Protection. Install updates from System Settings › General › Software Update."),
        ("shippingbox.circle", "Docker, VMs and app data",
         "Use the app’s own tools — for example Docker Desktop › Troubleshoot or `docker system prune`."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.slate)
                Text("Managed by macOS or other apps").font(.headline)
                Text("SpaceSweep never touches these").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.title) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.slate)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(item.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14, radius: Theme.rowRadius)
                }
            }
        }
    }
}
