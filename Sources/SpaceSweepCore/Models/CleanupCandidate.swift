import Foundation

/// Identity of a file-system object captured at scan time. If the object at a path
/// no longer matches its fingerprint at cleanup time, the target is rejected and a rescan is required.
public struct CandidateFingerprint: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let kind: FileStatus.Kind
    public let birthTime: Double?

    public init(device: UInt64, inode: UInt64, kind: FileStatus.Kind, birthTime: Double? = nil) {
        self.device = device
        self.inode = inode
        self.kind = kind
        self.birthTime = birthTime
    }

    public init(_ status: FileStatus) {
        self.init(device: status.device, inode: status.inode, kind: status.kind, birthTime: status.birthTime)
    }
}

/// One thing SpaceSweep found. Candidates are produced only by the scanner.
public struct CleanupCandidate: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let ruleID: String
    /// Absolute location. Kept in memory only; never persisted by default.
    public let url: URL
    public let rootURL: URL
    public let displayName: String
    /// Privacy-conscious, home-relative path such as `~/Library/Caches/Yarn/v6`.
    public let displayPath: String
    public let estimatedBytes: Int64
    public let itemCount: Int
    public let modifiedAt: Date?
    public let tier: SafetyTier
    public let blockedReason: String?
    public let fingerprint: CandidateFingerprint?
    public let isSelectedByDefault: Bool
    /// True when some files could not be read and the size is a lower bound.
    public let sizeIsPartial: Bool

    public init(
        id: UUID = UUID(),
        ruleID: String,
        url: URL,
        rootURL: URL,
        displayName: String,
        displayPath: String,
        estimatedBytes: Int64,
        itemCount: Int,
        modifiedAt: Date?,
        tier: SafetyTier,
        blockedReason: String?,
        fingerprint: CandidateFingerprint?,
        isSelectedByDefault: Bool,
        sizeIsPartial: Bool
    ) {
        self.id = id
        self.ruleID = ruleID
        self.url = url
        self.rootURL = rootURL
        self.displayName = displayName
        self.displayPath = displayPath
        self.estimatedBytes = estimatedBytes
        self.itemCount = itemCount
        self.modifiedAt = modifiedAt
        self.tier = tier
        self.blockedReason = blockedReason
        self.fingerprint = fingerprint
        self.isSelectedByDefault = isSelectedByDefault && tier == .safe
        self.sizeIsPartial = sizeIsPartial
    }

    /// Protected and blocked candidates can never be selected.
    public var isSelectable: Bool { tier.isDeletableTier && fingerprint != nil }
}
