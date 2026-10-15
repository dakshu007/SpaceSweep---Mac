import Foundation

public enum PlanError: Error, Equatable, Sendable {
    /// The scan is too old to act on. Rescan first.
    case scanExpired
    /// Nothing eligible was selected.
    case nothingSelected

    public var userMessage: String {
        switch self {
        case .scanExpired: return "These results are more than 10 minutes old. Rescan before cleaning."
        case .nothingSelected: return "Nothing eligible is selected."
        }
    }
}

/// Turns a scan report plus a selection into an immutable cleanup plan.
/// Protected, blocked and unknown items can never enter a plan.
public struct CleanupPlanner: Sendable {
    /// Plans are only built from fresh scans.
    public static let maximumScanAge: TimeInterval = 10 * 60

    public let registry: CleanupRuleRegistry
    private let now: @Sendable () -> Date

    public init(registry: CleanupRuleRegistry = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.registry = registry
        self.now = now
    }

    /// Plan from the user's explicit selection on the review screen.
    public func makePlan(from report: ScanReport, selectedIDs: Set<UUID>) throws -> CleanupPlan {
        try build(from: report, mode: .reviewed) { selectedIDs.contains($0.id) }
    }

    /// Plan for One-click Safe Clean: only default-selected Safe-tier candidates. Review is never included.
    public func makeOneClickPlan(from report: ScanReport) throws -> CleanupPlan {
        try build(from: report, mode: .oneClickSafe) { $0.tier == .safe && $0.isSelectedByDefault }
    }

    private func build(from report: ScanReport, mode: CleanupPlan.Mode, include: (CleanupCandidate) -> Bool) throws -> CleanupPlan {
        let current = now()
        guard current.timeIntervalSince(report.finishedAt) <= Self.maximumScanAge,
              current >= report.startedAt else { throw PlanError.scanExpired }

        var targets: [PlannedTarget] = []
        var excludedReviewCount = 0
        var excludedReviewBytes: Int64 = 0
        var permanent = false
        var seen = Set<String>()

        for candidate in report.allCandidates {
            let included = include(candidate)
            guard included, let target = eligibleTarget(candidate, mode: mode) else {
                if candidate.tier == .review {
                    excludedReviewCount += 1
                    excludedReviewBytes = excludedReviewBytes.saturatingAdd(candidate.estimatedBytes)
                }
                continue
            }
            guard seen.insert(candidate.url.standardizedFileURL.path).inserted else { continue }
            if registry.rule(id: candidate.ruleID)?.removesUserFilesPermanently == true { permanent = true }
            targets.append(target)
        }
        guard !targets.isEmpty else { throw PlanError.nothingSelected }
        return CleanupPlan(createdAt: current, scanFinishedAt: report.finishedAt, mode: mode, targets: targets,
                           excludedReviewCount: excludedReviewCount, excludedReviewBytes: excludedReviewBytes,
                           removesUserFilesPermanently: permanent)
    }

    private func eligibleTarget(_ candidate: CleanupCandidate, mode: CleanupPlan.Mode) -> PlannedTarget? {
        guard candidate.isSelectable,
              let fingerprint = candidate.fingerprint,
              let rule = registry.rule(id: candidate.ruleID),
              rule.isDeletable,
              candidate.tier == rule.tier else { return nil }
        if mode == .oneClickSafe && (rule.tier != .safe || rule.removesUserFilesPermanently) { return nil }
        return PlannedTarget(candidate: candidate, rule: rule, fingerprint: fingerprint)
    }
}
