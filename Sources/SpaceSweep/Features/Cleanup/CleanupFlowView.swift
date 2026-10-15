import SpaceSweepCore
import SwiftUI

/// One sheet that walks through confirm → progress → results.
struct CleanupFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.cleanupFlow {
            case .confirming(let plan):
                ConfirmationView(plan: plan)
            case .running(let plan, let progress):
                CleanupProgressView(plan: plan, progress: progress)
            case .finished(let report):
                CleanupResultView(report: report)
            case nil:
                EmptyView()
            }
        }
        .frame(width: 580)
        .frame(minHeight: 460)
    }
}

// MARK: - Confirm

private struct ConfirmationView: View {
    @Environment(AppModel.self) private var model
    let plan: CleanupPlan
    @State private var acknowledgedPermanent = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.brandGradient).frame(width: 64, height: 64)
                        .shadow(color: Theme.indigo.opacity(0.4), radius: 14, y: 6)
                    Image(systemName: "sparkles").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                }
                Text("Ready to clean").font(.title2.weight(.bold))
                Text("≈ \(Format.bytes(plan.estimatedBytes))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.brandGradient)
                Text("\(Format.count(plan.targets.count, "item")) in \(Format.count(plan.ruleGroups.count, "category", "categories")) · estimated")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(plan.ruleGroups, id: \.ruleID) { group in
                        let rule = model.registry.rule(id: group.ruleID)
                        HStack(spacing: 12) {
                            IconTile(symbol: rule?.symbolName ?? "folder", color: Theme.color(for: rule?.category ?? .appCache), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).font(.callout.weight(.semibold))
                                Text(rule?.consequence ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            SafetyBadge(tier: group.tier, compact: true)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Format.bytes(group.bytes)).font(.callout.weight(.semibold)).monospacedDigit()
                                Text(Format.count(group.count, "item")).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 70, alignment: .trailing)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 220)

            VStack(alignment: .leading, spacing: 10) {
                note(symbol: "arrow.triangle.2.circlepath", color: Theme.indigo,
                     text: "Selected cache and build data will be deleted. Tools will regenerate or re-download it when needed.")
                if plan.containsReviewItems {
                    note(symbol: "eye.fill", color: Theme.amber,
                         text: "Your selection includes Review items you chose yourself. Check the details above before continuing.")
                }
                if plan.excludedReviewCount > 0 {
                    note(symbol: "minus.circle", color: Theme.slate,
                         text: "\(Format.count(plan.excludedReviewCount, "Review item")) (\(Format.bytes(plan.excludedReviewBytes))) not selected and won’t be touched.")
                }
                if plan.includesPermanentUserFileRemoval {
                    VStack(alignment: .leading, spacing: 8) {
                        note(symbol: "trash.fill", color: Theme.amber,
                             text: "Items in the Trash will be permanently removed. They can’t be recovered afterwards.")
                        Toggle("I understand the Trash items will be permanently removed", isOn: $acknowledgedPermanent)
                            .toggleStyle(.checkbox)
                            .font(.callout)
                            .padding(.leading, 30)
                    }
                }
                if !model.hasConfirmedFirstClean {
                    note(symbol: "hand.raised.fill", color: Theme.teal,
                         text: "You’ll see this summary before every cleanup. Later you can turn on One-click Safe Clean in Settings — it only ever includes Safe items.")
                }
            }
            .padding(24)

            Divider()

            HStack {
                Button("Cancel") { model.dismissCleanupFlow() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    model.confirm(plan)
                } label: {
                    Label("Clean \(Format.count(plan.targets.count, "Item"))", systemImage: "sparkles")
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(plan.includesPermanentUserFileRemoval && !acknowledgedPermanent)
            }
            .padding(18)
        }
    }

    private func note(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Progress

private struct CleanupProgressView: View {
    @Environment(AppModel.self) private var model
    let plan: CleanupPlan
    let progress: CleanupProgress
    @State private var cancelRequested = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress.fraction))
                        .stroke(Theme.ringGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.snappy, value: progress.fraction)
                    VStack(spacing: 0) {
                        Text("\(Int((progress.fraction * 100).rounded()))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: progress.fraction))
                        Text("\(progress.completedTargets)/\(progress.totalTargets)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .frame(width: 120, height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cleanup progress")
                .accessibilityValue("\(progress.completedTargets) of \(progress.totalTargets) items")

                Text(cancelRequested ? "Stopping after the current item…" : "Cleaning")
                    .font(.title2.weight(.bold))
                if let rule = progress.currentRuleTitle, let item = progress.currentItemName {
                    Text("\(rule) · \(item)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("≈ \(Format.bytes(progress.bytesRemoved)) of files removed so far")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.bytesRemoved)))
                    .animation(.snappy, value: progress.bytesRemoved)
            }
            .padding(.top, 30)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(plan.ruleGroups, id: \.ruleID) { group in
                        HStack(spacing: 10) {
                            statusIcon(for: group.ruleID)
                                .frame(width: 20)
                            Text(group.title).font(.callout)
                            Spacer()
                            Text(Format.count(group.count, "item")).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(progress.currentRuleID == group.ruleID ? Theme.indigo.opacity(0.10) : Color.primary.opacity(0.035)))
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 200)

            HStack(spacing: 18) {
                Label("\(progress.deleted) removed", systemImage: "checkmark.circle").foregroundStyle(Theme.mint)
                Label("\(progress.skipped) skipped", systemImage: "arrow.uturn.right.circle").foregroundStyle(.secondary)
                Label("\(progress.failed) failed", systemImage: "exclamationmark.circle").foregroundStyle(progress.failed > 0 ? Theme.amber : .secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.vertical, 14)

            Divider()
            HStack {
                Spacer()
                Button("Stop") {
                    cancelRequested = true
                    model.cancelCleanup()
                }
                .buttonStyle(.secondary)
                .disabled(cancelRequested)
                .keyboardShortcut(.cancelAction)
                .help("No new items will be started. The current item finishes safely.")
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func statusIcon(for ruleID: String) -> some View {
        let groupIndex = plan.ruleGroups.firstIndex { $0.ruleID == ruleID } ?? 0
        let currentIndex = plan.ruleGroups.firstIndex { $0.ruleID == progress.currentRuleID } ?? -1
        if progress.currentRuleID == ruleID {
            ProgressView().controlSize(.small)
        } else if groupIndex < currentIndex {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Results

private struct CleanupResultView: View {
    @Environment(AppModel.self) private var model
    let report: CleanupReport
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    SparkleBurst(trigger: celebrate)
                    Circle().fill(statusGradient).frame(width: 72, height: 72)
                        .shadow(color: statusColor.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: statusSymbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: celebrate)
                }
                .frame(height: 90)
                Text(title).font(.title2.weight(.bold))

                if let change = report.measuredFreeSpaceChange {
                    Text("+\(Format.bytes(change))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brandGradient)
                    Text("free-space change measured on disk")
                        .font(.callout).foregroundStyle(.secondary)
                } else if !report.wasDryRun && report.deletedItems > 0 {
                    Text("Free-space change: unable to measure reliably")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Other apps, snapshots and macOS also change free space, so SpaceSweep doesn’t guess.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("≈ \(Format.bytes(report.bytesRemoved)) of files removed · \(Format.bytes(report.estimatedBytesAttempted)) was estimated")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            HStack(spacing: 10) {
                countTile(report.deletedItems, "Cleaned", Theme.mint, "checkmark.circle.fill")
                countTile(report.skippedItems, "Skipped", Theme.slate, "arrow.uturn.right.circle.fill")
                countTile(report.failedItems, "Failed", Theme.amber, "exclamationmark.circle.fill")
                countTile(report.cancelledItems, "Not started", Theme.slate, "stop.circle.fill")
            }
            .padding(.horizontal, 24)

            let problems = report.rules.filter { !$0.problems.isEmpty }
            if !problems.isEmpty || !report.messages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.messages, id: \.self) { message in
                            Label(message, systemImage: "info.circle").font(.callout)
                        }
                        ForEach(problems) { rule in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.ruleTitle).font(.callout.weight(.semibold))
                                ForEach(rule.problems, id: \.self) { problem in
                                    Label(problem, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 150)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }

            Text("System Settings › Storage may take a while to refresh its categories after a cleanup.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)

            Divider().padding(.top, 16)
            HStack {
                Button("View Activity") {
                    model.dismissCleanupFlow()
                    model.route = .activity
                }
                .buttonStyle(.secondary)
                Spacer()
                Button {
                    model.dismissCleanupFlow()
                    model.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
                Button("Done") { model.dismissCleanupFlow() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .onAppear {
            if report.overallStatus == .success { celebrate = true }
        }
    }

    private var title: String {
        if report.wasDryRun { return "Dry run complete" }
        switch report.overallStatus {
        case .success: return "All clean"
        case .partial: return "Partly cleaned"
        case .failed: return "Nothing could be cleaned"
        case .cancelled: return "Cleanup stopped"
        case .nothingDone: return "Nothing was cleaned"
        }
    }

    private var statusColor: Color {
        switch report.overallStatus {
        case .success: return Theme.mint
        case .partial, .cancelled: return Theme.amber
        case .failed, .nothingDone: return Theme.slate
        }
    }

    private var statusGradient: LinearGradient {
        report.overallStatus == .success ? Theme.brandGradient : Theme.gradient(for: statusColor)
    }

    private var statusSymbol: String {
        switch report.overallStatus {
        case .success: return "checkmark"
        case .partial: return "checkmark.circle.trianglebadge.exclamationmark"
        case .failed: return "xmark"
        case .cancelled: return "stop.fill"
        case .nothingDone: return "minus"
        }
    }

    private func countTile(_ value: Int, _ label: String, _ color: Color, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("\(value)").font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}
