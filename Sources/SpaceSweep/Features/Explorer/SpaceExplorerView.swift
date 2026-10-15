import SpaceSweepCore
import SwiftUI

/// "Where's my space?" — a read-only look behind macOS's System Data number.
struct SpaceExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var group: ExplorerEntry.Group?
    @State private var showSkipped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if model.explorerReport != nil {
                    folders
                    managedByMacOS
                } else {
                    managedByMacOS
                    folders
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .onAppear { if model.insights == nil { model.refreshInsights() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            IconTile(symbol: "chart.pie.fill", color: Theme.violet, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text("Where’s my space?").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("macOS lumps thousands of folders into “System Data”. Space Explorer measures the ones behind it so you can see what’s really there. It’s read-only — nothing is deleted from this screen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch model.explorerState {
            case .running(let progress):
                VStack(alignment: .trailing, spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 180)
                    Text(progress.currentFolder.isEmpty ? "Preparing…" : progress.currentFolder)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .frame(width: 220, alignment: .trailing)
                    Text("\(Format.bytes(progress.measuredBytes)) measured")
                        .font(.caption.weight(.medium)).monospacedDigit()
                    Button("Cancel") { model.cancelExplorer() }
                        .buttonStyle(.secondary)
                }
            default:
                Button {
                    model.startExplorer()
                } label: {
                    Label(model.explorerReport == nil ? "Analyze" : "Analyze Again", systemImage: "chart.pie")
                }
                .buttonStyle(.primary)
            }
        }
        .card(padding: 22, radius: 24)
    }

    // MARK: Managed by macOS

    private var managedByMacOS: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Managed by macOS").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                InsightCard(
                    symbol: "apple.logo", color: Theme.slate, title: "macOS itself",
                    value: model.volume == nil ? "—" : "Not reducible",
                    detail: "The “macOS” bar in System Settings is the operating system on a sealed, read-only volume. 25–35 GB is normal and no app can safely shrink it.",
                    steps: ["Keep macOS up to date — updates replace the system rather than adding to it.",
                            "Never use tools that claim to “slim” macOS; they break the signed system."],
                    commands: []
                )
                InsightCard(
                    symbol: "arrow.3.trianglepath", color: Theme.teal, title: "Purgeable space",
                    value: model.insights?.purgeableBytes.map(Format.bytes) ?? "—",
                    detail: "Caches and snapshots macOS will free automatically the moment space is needed. It’s already counted in “Available”.",
                    steps: ["Nothing to do — macOS reclaims this on demand.",
                            "Restarting your Mac often releases some of it immediately."],
                    commands: []
                )
                InsightCard(
                    symbol: "memorychip", color: Theme.indigo, title: "Swap & sleep image",
                    value: swapValue,
                    detail: "Virtual memory files in /private/var/vm. They grow when memory is tight and are counted in System Data.",
                    steps: ["Restart your Mac — swap files are recreated small.",
                            "Quit memory-heavy apps (browsers with many tabs, Docker, VMs) you’re not using."],
                    commands: ["sysctl vm.swapusage"]
                )
                InsightCard(
                    symbol: "clock.arrow.circlepath", color: Theme.mint, title: "Time Machine local snapshots",
                    value: model.insights?.localSnapshotCount.map { Format.count($0, "snapshot") } ?? "—",
                    detail: "Hourly local backups. macOS deletes them automatically when space runs low, but they can inflate System Data in the meantime.",
                    steps: ["List them with the first command in Terminal.",
                            "Optional: ask macOS to release up to the space you need with the second command (it removes the oldest snapshots first).",
                            "Snapshots are only a convenience — your Time Machine backup disk is unaffected."],
                    commands: ["tmutil listlocalsnapshots /", "tmutil thinlocalsnapshots / 999999999999 4"]
                )
                InsightCard(
                    symbol: "iphone.gen3", color: Theme.color(for: .simulator), title: "Simulator runtimes",
                    value: model.insights?.simulatorRuntimeBytes.map(Format.bytes) ?? "None found",
                    detail: "iOS, watchOS and visionOS simulator runtimes Xcode downloaded. Each one is 5–10 GB and lives outside your home folder.",
                    steps: ["Open Xcode › Settings › Components (or Platforms) and delete runtimes you no longer test on.",
                            "Remove simulators whose runtime is gone with the second command."],
                    commands: ["xcrun simctl runtime list", "xcrun simctl delete unavailable"]
                )
                if model.insights?.dockerInstalled == true || model.insights?.orbStackInstalled == true {
                    InsightCard(
                        symbol: "shippingbox.circle.fill", color: Theme.color(for: .devTools), title: "Docker disk image",
                        value: "Check in Docker",
                        detail: "Docker keeps every image, container and volume in one large disk image (often 20–60 GB) that counts as System Data.",
                        steps: ["See what’s using space with the first command.",
                                "Remove unused images, containers and build cache with the second (it asks before deleting).",
                                "Docker Desktop › Settings › Resources lets you cap the disk image size."],
                        commands: ["docker system df", "docker system prune -a"]
                    )
                }
            }
        }
    }

    private var swapValue: String {
        guard let insights = model.insights else { return "—" }
        let total = (insights.swapUsedBytes ?? 0).saturatingAdd(insights.sleepImageBytes ?? 0)
        if insights.swapUsedBytes == nil && insights.sleepImageBytes == nil { return "—" }
        return Format.bytes(total)
    }

    // MARK: Folders

    @ViewBuilder
    private var folders: some View {
        if let report = model.explorerReport {
            let entries = report.entries.filter { group == nil || $0.group == group }
            let maxBytes = entries.first?.bytes ?? 1
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Largest folders").font(.headline)
                        Text("\(Format.bytes(report.totalBytes)) measured · \(Format.bytes(report.coveredBytes)) in folders SpaceSweep has cleanup rules for · analyzed \(Format.relative(report.finishedAt, now: model.clock))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Show", selection: $group) {
                        Text("All").tag(ExplorerEntry.Group?.none)
                        ForEach(ExplorerEntry.Group.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 420)
                }
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(40).enumerated()), id: \.element.id) { index, entry in
                        FolderRow(entry: entry, fraction: Double(entry.bytes) / Double(max(maxBytes, 1)))
                        if index < min(entries.count, 40) - 1 { Divider().padding(.leading, 56) }
                    }
                    if entries.isEmpty {
                        Text("Nothing large found here.").foregroundStyle(.secondary).padding(20)
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))

                DisclosureGroup(isExpanded: $showSkipped) {
                    Text((report.skippedPrivateFolders + report.unreadableFolders).joined(separator: "  ·  "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } label: {
                    Label("\(report.skippedPrivateFolders.count + report.unreadableFolders.count) folders not opened for privacy (mail, messages, app containers, iCloud, keys…)",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !model.isExploring {
            EmptyStateView(symbol: "chart.pie", title: "See what’s inside System Data",
                           message: "Analyze measures your Library, app data, developer folders and hidden tool folders. It takes a minute or two and changes nothing.") {
                Button {
                    model.startExplorer()
                } label: {
                    Label("Analyze", systemImage: "chart.pie")
                }
                .buttonStyle(.primaryLarge)
            }
            .frame(minHeight: 280)
        }
    }
}

// MARK: - Rows & cards

private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    let entry: ExplorerEntry
    let fraction: Double
    @State private var hovering = false

    private var rules: [CleanupRule] { entry.coveringRuleIDs.compactMap { model.registry.rule(id: $0) } }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: rules.isEmpty ? Theme.slate : Theme.color(for: rules[0].category), size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name).font(.callout.weight(.semibold)).lineLimit(1)
                    if !rules.isEmpty {
                        StatusChip(text: rules.count == 1 ? rules[0].title : "\(rules.count) cleanup rules",
                                   symbol: "sparkles", color: Theme.accent)
                            .help("SpaceSweep can clean parts of this folder: " + rules.map(\.title).joined(separator: ", "))
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(rules.isEmpty ? AnyShapeStyle(Theme.slate.opacity(0.6)) : AnyShapeStyle(Theme.brandGradient))
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
                }
                .frame(height: 5)
                Text(entry.displayPath).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text((entry.isPartial ? "≥ " : "") + Format.bytes(entry.bytes))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                Text(rules.isEmpty ? "Managed by its app" : "Partly cleanable")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 110, alignment: .trailing)
            if !rules.isEmpty {
                Button("Review") {
                    model.route = .results
                    if model.report == nil || model.reportIsStale { model.startScan() }
                }
                .buttonStyle(.secondary)
                .help("Open Scan Results to choose what to clean")
            }
            Button {
                model.revealFolder(entry.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(GhostIconButtonStyle())
            .help("Show this folder in Finder")
            .accessibilityLabel("Show \(entry.name) in Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        if let rule = rules.first { return rule.symbolName }
        switch entry.group {
        case .library: return "books.vertical.fill"
        case .applicationSupport: return "app.fill"
        case .developer: return "hammer.fill"
        case .hidden: return "eye.slash.fill"
        }
    }
}

private struct InsightCard: View {
    @Environment(AppModel.self) private var model
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let detail: String
    let steps: [String]
    let commands: [String]
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconTile(symbol: symbol, color: color, size: 32)
                Spacer()
                Button {
                    showHelp.toggle()
                } label: {
                    Label("How to reclaim", systemImage: "lightbulb")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.secondary)
                .popover(isPresented: $showHelp, arrowEdge: .bottom) { help }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 16)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Circle().fill(color))
                    Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !commands.isEmpty {
                Text("Run in Terminal yourself — SpaceSweep never runs these for you:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(commands, id: \.self) { command in
                    HStack {
                        Text(command).font(.callout.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button {
                            model.copyToPasteboard(command)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(GhostIconButtonStyle())
                        .help("Copy")
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
