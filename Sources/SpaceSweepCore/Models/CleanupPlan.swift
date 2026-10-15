import Foundation

/// A target the executor may act on. Created only by `CleanupPlanner` from a scan report —
/// the UI layer cannot construct one from an arbitrary path.
public struct PlannedTarget: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let ruleID: String
    public let ruleTitle: String
    public let displayName: String
    public let displayPath: String
    public let estimatedBytes: Int64
    public let itemCount: Int
    public let tier: SafetyTier
    let url: URL
    let rootURL: URL
    let fingerprint: CandidateFingerprint

    init(candidate: CleanupCandidate, rule: CleanupRule, fingerprint: CandidateFingerprint) {
        self.id = candidate.id
        self.ruleID = rule.id
        self.ruleTitle = rule.title
        self.displayName = candidate.displayName
        self.displayPath = candidate.displayPath
        self.estimatedBytes = candidate.estimatedBytes
        self.itemCount = candidate.itemCount
        self.tier = candidate.tier
        self.url = candidate.url
        self.rootURL = candidate.rootURL
        self.fingerprint = fingerprint
    }

    /// Test-only constructor, used to prove the executor revalidates whatever it is given.
    init(id: UUID = UUID(), ruleID: String, ruleTitle: String, url: URL, rootURL: URL, tier: SafetyTier,
         estimatedBytes: Int64, fingerprint: CandidateFingerprint) {
        self.id = id
        self.ruleID = ruleID
        self.ruleTitle = ruleTitle
        self.displayName = url.lastPathComponent
        self.displayPath = url.path
        self.estimatedBytes = estimatedBytes
        self.itemCount = 0
        self.tier = tier
        self.url = url
        self.rootURL = rootURL
        self.fingerprint = fingerprint
    }
}

public struct CleanupPlan: Sendable, Identifiable {
    public enum Mode: String, Sendable, Codable {
        /// Built from the user's explicit selection on the review screen.
        case reviewed
        /// Built automatically from the fixed Safe tier only.
        case oneClickSafe
    }

    public enum Authorization: Sendable, Equatable {
        case pendingConfirmation
        case userConfirmed
        /// The user enabled One-click Safe Clean in Settings. Valid for Safe-only plans.
        case oneClickPreference
    }

    public let id: UUID
    public let createdAt: Date
    public let scanFinishedAt: Date
    public let mode: Mode
    public let targets: [PlannedTarget]
    /// Review-tier candidates found by the scan but not included in this plan.
    public let excludedReviewCount: Int
    public let excludedReviewBytes: Int64
    public private(set) var authorization: Authorization
    let removesUserFilesPermanently: Bool

    init(id: UUID = UUID(), createdAt: Date, scanFinishedAt: Date, mode: Mode, targets: [PlannedTarget],
         excludedReviewCount: Int, excludedReviewBytes: Int64, removesUserFilesPermanently: Bool,
         authorization: Authorization = .pendingConfirmation) {
        self.id = id
        self.createdAt = createdAt
        self.scanFinishedAt = scanFinishedAt
        self.mode = mode
        self.targets = targets
        self.excludedReviewCount = excludedReviewCount
        self.excludedReviewBytes = excludedReviewBytes
        self.removesUserFilesPermanently = removesUserFilesPermanently
        self.authorization = authorization
    }

    public var estimatedBytes: Int64 { targets.reduce(0) { $0.saturatingAdd($1.estimatedBytes) } }
    public var containsReviewItems: Bool { targets.contains { $0.tier == .review } }
    public var includesPermanentUserFileRemoval: Bool { removesUserFilesPermanently }
    public var isEmpty: Bool { targets.isEmpty }

    /// Targets grouped by rule, preserving plan order.
    public var ruleGroups: [(ruleID: String, title: String, bytes: Int64, count: Int, tier: SafetyTier)] {
        var order: [String] = []
        var groups: [String: (String, Int64, Int, SafetyTier)] = [:]
        for target in targets {
            if groups[target.ruleID] == nil { order.append(target.ruleID) }
            let existing = groups[target.ruleID] ?? (target.ruleTitle, 0, 0, target.tier)
            groups[target.ruleID] = (existing.0, existing.1.saturatingAdd(target.estimatedBytes), existing.2 + 1, existing.3)
        }
        return order.compactMap { id in
            groups[id].map { (ruleID: id, title: $0.0, bytes: $0.1, count: $0.2, tier: $0.3) }
        }
    }

    /// The user reviewed this plan and confirmed it.
    public func confirmedByUser() -> CleanupPlan {
        var copy = self
        copy.authorization = .userConfirmed
        return copy
    }

    /// Authorise via the One-click Safe Clean preference. Refused unless every target is Safe.
    public func authorizedByOneClickPreference() -> CleanupPlan? {
        guard mode == .oneClickSafe, targets.allSatisfy({ $0.tier == .safe }), !removesUserFilesPermanently else {
            return nil
        }
        var copy = self
        copy.authorization = .oneClickPreference
        return copy
    }
}
