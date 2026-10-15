import SpaceSweepCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HeroCard()
                if let report = model.report {
                    TierSummaryRow(report: report)
                    HStack(alignment: .top, spacing: 20) {
                        BreakdownCard(report: report)
                        TopItemsCard(report: report)
                    }
                } else {
                    FirstScanCard()
                }
                if let cleanup = model.lastCleanup {
                    LastCleanupCard(report: cleanup)
                }
                SystemDataNote()
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            ring
                .frame(width: 230, height: 230)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subheadline)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
                if let volume = model.volume {
                    CapacityBar(usedBytes: volume.usedBytes, availableBytes: volume.availableBytes, totalBytes: volume.totalBytes)
                        .padding(.top, 6)
                }
                lastScanLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 28, radius: 26)
    }

    @ViewBuilder
    private var ring: some View {
        if let volume = model.volume {
            StorageRing(usedFraction: volume.usedFraction) {
                VStack(spacing: 2) {
                    Text("Available")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    let parts = Format.bytesParts(volume.availableBytes)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(parts.value)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(volume.availableBytes)))
                        Text(parts.unit)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    Text("of \(Format.bytes(volume.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy, value: volume.availableBytes)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Available storage")
            .accessibilityValue("\(Format.bytes(volume.availableBytes)) available of \(Format.bytes(volume.totalBytes))")
        } else {
            StorageRing(usedFraction: 0) {
                VStack(spacing: 6) {
                    Image(systemName: model.volumeUnavailable ? "exclamationmark.triangle" : "internaldrive")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(model.volumeUnavailable ? "Capacity unavailable" : "Reading storage…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var headline: String {
        if model.report != nil, model.selectedBytes > 0 { return "\(Format.bytes(model.selectedBytes)) ready to sweep" }
        if model.report != nil { return "Your scan is ready" }
        return "Find what’s taking space."
    }

    private var subheadline: String {
        if let report = model.report {
            let review = report.bytes(in: .review)
            if model.selectedBytes > 0 {
                return review > 0
                    ? "Safe items are selected. \(Format.bytes(review)) more is waiting for your review."
                    : "Only known, rebuildable data is selected."
            }
            return review > 0 ? "Nothing is selected yet. \(Format.bytes(review)) can be reviewed." : "Nothing cleanable was found right now."
        }
        return "Clean only what’s safe. Keep the files that matter."
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if model.canOneClick {
                Button {
                    model.oneClickSafeClean()
                } label: {
                    Label("One-click Safe Clean", systemImage: "sparkles")
                }
                .buttonStyle(.primaryLarge)
                .disabled(model.isScanning || model.isCleaning)
                .help("Scans, then cleans Safe items only. Review items are never included.")
                Button("Scan & Review") { model.startScan() }
                    .buttonStyle(.secondaryLarge)
                    .disabled(model.isScanning || model.isCleaning)
            } else if model.report != nil && !model.reportIsStale {
                Button {
                    model.route = .results
                } label: {
                    Label("Review & Clean", systemImage: "wand.and.stars")
                }
                .buttonStyle(.primaryLarge)
                Button("Rescan") { model.startScan() }
                    .buttonStyle(.secondaryLarge)
                    .disabled(model.isScanning || model.isCleaning)
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan Mac", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.primaryLarge)
                .disabled(model.isScanning || model.isCleaning)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var lastScanLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            if let date = model.lastScanDate {
                Text("Last scan \(Format.relative(date, now: model.clock))")
                if model.reportIsStale { Text("· results expired, rescan before cleaning") }
            } else {
                Text("Not scanned yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Tiers

private struct TierSummaryRow: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    var body: some View {
        HStack(spacing: 16) {
            StatTile(title: "Safe to clean", value: report.bytes(in: .safe),
                     caption: "\(Format.count(report.count(in: .safe), "item")) · rebuilt automatically",
                     symbol: Theme.symbol(for: .safe), color: Theme.color(for: .safe))
            StatTile(title: "Review first", value: report.bytes(in: .review),
                     caption: "\(Format.count(report.count(in: .review), "item")) · never auto-selected",
                     symbol: Theme.symbol(for: .review), color: Theme.color(for: .review))
            StatTile(title: "Unavailable now", value: report.bytes(in: .blocked),
                     caption: report.count(in: .blocked) > 0 ? "Quit the related app, then rescan" : "Nothing blocked",
                     symbol: Theme.symbol(for: .blocked), color: Theme.color(for: .blocked))
            StatTile(title: "Protected", value: report.bytes(in: .protected),
                     caption: "Shown for context · never cleaned",
                     symbol: Theme.symbol(for: .protected), color: Theme.color(for: .protected))
        }
    }
}

private struct BreakdownCard: View {
    let report: ScanReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SpaceSweep scan results")
                    .font(.headline)
                Spacer()
                if report.isPartial {
                    StatusChip(text: "Partial", symbol: "exclamationmark.circle", color: Theme.amber)
                        .help("Some locations couldn’t be read. See Scan Results for details.")
                }
            }
            let segments = report.bytesByCategory()
            if segments.isEmpty {
                Text("No cleanable data was found in the locations SpaceSweep knows about.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CategoryBar(segments: segments)
            }
            Text("Sizes are estimates of allocated space. macOS’s own Storage categories are measured differently.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }
}

private struct TopItemsCard: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    private var top: [CleanupCandidate] {
        Array(report.allCandidates.filter { $0.tier != .protected }.sorted { $0.estimatedBytes > $1.estimatedBytes }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Largest finds").font(.headline)
                Spacer()
                Button("See all") { model.route = .results }
                    .buttonStyle(.link)
            }
            if top.isEmpty {
                Text("Nothing to show yet.").foregroundStyle(.secondary)
            }
            ForEach(top) { candidate in
                let rule = model.registry.rule(id: candidate.ruleID)
                HStack(spacing: 10) {
                    IconTile(symbol: rule?.symbolName ?? "folder", color: Theme.color(for: rule?.category ?? .appCache), size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.displayName).font(.callout.weight(.medium)).lineLimit(1)
                        Text(rule?.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    SafetyBadge(tier: candidate.tier, compact: true)
                    Text(Format.bytes(candidate.estimatedBytes))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }
}

// MARK: - Empty / info

private struct FirstScanCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            feature(symbol: "scope", color: Theme.teal, title: "Targeted",
                    text: "Looks only in known locations like Xcode DerivedData and the npm cache — never your whole disk.")
            feature(symbol: "checkmark.shield.fill", color: Theme.mint, title: "Safe by default",
                    text: "Only rebuildable data is pre-selected. Everything else waits for your review.")
            feature(symbol: "lock.fill", color: Theme.indigo, title: "Private",
                    text: "Everything stays on this Mac. No accounts, network or telemetry.")
        }
    }

    private func feature(symbol: String, color: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: symbol, color: color, size: 36)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }
}

private struct LastCleanupCard: View {
    @Environment(AppModel.self) private var model
    let report: CleanupReport

    var body: some View {
        HStack(spacing: 16) {
            IconTile(symbol: report.overallStatus == .success ? "checkmark" : "exclamationmark",
                     color: report.overallStatus == .success ? Theme.mint : Theme.amber, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Last cleanup · \(Format.relative(report.finishedAt, now: model.clock))").font(.headline)
                Text("\(report.deletedItems) removed · \(report.failedItems) failed · \(report.skippedItems + report.cancelledItems) skipped · ≈ \(Format.bytes(report.bytesRemoved)) of files")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let change = report.measuredFreeSpaceChange {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(Format.bytes(change))").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.mint)
                    Text("free space measured").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Activity") { model.route = .activity }
                .buttonStyle(.secondary)
        }
        .card()
    }
}

private struct SystemDataNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text("About “System Data”")
                    .font(.subheadline.weight(.semibold))
                Text("System Data is a macOS category, not one folder. SpaceSweep only cleans known targets it can explain. Time Machine snapshots, swap and macOS files are managed by macOS and are never touched, and System Settings may take a while to update after a cleanup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}
