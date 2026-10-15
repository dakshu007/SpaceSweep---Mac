import Foundation

public enum ScanPhase: Int, Sendable, CaseIterable, Comparable {
    case checkingStorage
    case discovering
    case measuring
    case validating
    case finalising

    public var title: String {
        switch self {
        case .checkingStorage: return "Checking storage"
        case .discovering: return "Discovering known caches"
        case .measuring: return "Measuring candidates"
        case .validating: return "Validating safe paths"
        case .finalising: return "Finalising report"
        }
    }

    public static func < (lhs: ScanPhase, rhs: ScanPhase) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ScanProgress: Sendable, Equatable {
    public var phase: ScanPhase
    /// Files and folders actually examined so far.
    public var examinedItems: Int
    /// Bytes actually measured so far.
    public var measuredBytes: Int64
    public var candidatesFound: Int
    public var currentRuleTitle: String?
    public var completedRules: Int
    public var totalRules: Int

    public init(phase: ScanPhase, examinedItems: Int = 0, measuredBytes: Int64 = 0, candidatesFound: Int = 0,
                currentRuleTitle: String? = nil, completedRules: Int = 0, totalRules: Int = 0) {
        self.phase = phase
        self.examinedItems = examinedItems
        self.measuredBytes = measuredBytes
        self.candidatesFound = candidatesFound
        self.currentRuleTitle = currentRuleTitle
        self.completedRules = completedRules
        self.totalRules = totalRules
    }
}

/// Outcome of scanning a single rule's root.
public enum RuleScanStatus: Sendable, Equatable {
    case scanned
    case notFound
    case disabled
    case permissionDenied(mayNeedFullDiskAccess: Bool)
    case rootRejected(ValidationFailure)

    public var isProblem: Bool {
        switch self {
        case .permissionDenied, .rootRejected: return true
        case .scanned, .notFound, .disabled: return false
        }
    }

    public var message: String? {
        switch self {
        case .scanned: return nil
        case .notFound: return "Not found on this Mac."
        case .disabled: return "Rule turned off in Settings."
        case .permissionDenied(let fda):
            return fda
                ? "macOS privacy protections blocked access. Grant Full Disk Access in System Settings to measure this location."
                : "Permission denied by file ownership or access controls."
        case .rootRejected(let failure): return failure.userMessage
        }
    }
}

public struct RuleScanResult: Sendable, Identifiable {
    public var id: String { rule.id }
    public let rule: CleanupRule
    public let status: RuleScanStatus
    public let candidates: [CleanupCandidate]
    /// Running apps that block this rule.
    public let blockingApps: [KnownApp]
    public let skippedSymbolicLinks: Int
    public let skippedOverlaps: Int
    public let unreadableItems: Int

    public init(rule: CleanupRule, status: RuleScanStatus, candidates: [CleanupCandidate] = [],
                blockingApps: [KnownApp] = [], skippedSymbolicLinks: Int = 0, skippedOverlaps: Int = 0,
                unreadableItems: Int = 0) {
        self.rule = rule
        self.status = status
        self.candidates = candidates
        self.blockingApps = blockingApps
        self.skippedSymbolicLinks = skippedSymbolicLinks
        self.skippedOverlaps = skippedOverlaps
        self.unreadableItems = unreadableItems
    }

    public var totalBytes: Int64 { candidates.reduce(0) { $0.saturatingAdd($1.estimatedBytes) } }
    public var totalItems: Int { candidates.reduce(0) { $0 + $1.itemCount } }

    public func bytes(in tier: SafetyTier) -> Int64 {
        candidates.filter { $0.tier == tier }.reduce(0) { $0.saturatingAdd($1.estimatedBytes) }
    }
}

/// Immutable result of a scan. Plans built from a report expire after a short period.
public struct ScanReport: Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let volume: VolumeSnapshot?
    public let ruleResults: [RuleScanResult]

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date, volume: VolumeSnapshot?, ruleResults: [RuleScanResult]) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.volume = volume
        self.ruleResults = ruleResults
    }

    public var allCandidates: [CleanupCandidate] { ruleResults.flatMap(\.candidates) }

    /// True when at least one rule could not be fully inspected.
    public var isPartial: Bool {
        ruleResults.contains { $0.status.isProblem || $0.unreadableItems > 0 }
    }

    public func candidate(id: UUID) -> CleanupCandidate? {
        allCandidates.first { $0.id == id }
    }

    public func result(for ruleID: String) -> RuleScanResult? {
        ruleResults.first { $0.rule.id == ruleID }
    }

    public func bytes(in tier: SafetyTier) -> Int64 {
        allCandidates.filter { $0.tier == tier }.reduce(0) { $0.saturatingAdd($1.estimatedBytes) }
    }

    public func count(in tier: SafetyTier) -> Int {
        allCandidates.filter { $0.tier == tier }.count
    }

    /// Bytes per category, for the "SpaceSweep scan results" chart.
    public func bytesByCategory() -> [(category: RuleCategory, bytes: Int64)] {
        var totals: [RuleCategory: Int64] = [:]
        for result in ruleResults {
            totals[result.rule.category, default: 0] = totals[result.rule.category, default: 0].saturatingAdd(result.totalBytes)
        }
        return totals.filter { $0.value > 0 }
            .map { (category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    public var defaultSelection: Set<UUID> {
        Set(allCandidates.filter { $0.isSelectedByDefault && $0.isSelectable }.map(\.id))
    }

    public func age(now: Date = Date()) -> TimeInterval { now.timeIntervalSince(finishedAt) }
}
