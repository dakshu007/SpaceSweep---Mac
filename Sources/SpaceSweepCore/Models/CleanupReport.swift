import Foundation

/// Honest record of what a cleanup actually did. Estimated sizes are never presented as
/// filesystem bytes freed: `measuredFreeSpaceChange` is reported separately and only when measurable.
public struct CleanupReport: Codable, Sendable, Identifiable {
    public enum ItemStatus: String, Codable, Sendable {
        case deleted
        case failed
        case skipped
        case cancelled
    }

    public struct ItemOutcome: Codable, Sendable, Identifiable {
        public let id: UUID
        public let ruleID: String
        public let ruleTitle: String
        public let displayName: String
        public let displayPath: String
        public let status: ItemStatus
        public let estimatedBytes: Int64
        /// Approximate bytes of files removed (file-level measurement, not filesystem free space).
        public let bytesRemoved: Int64
        public let message: String?
    }

    public struct RuleSummary: Codable, Sendable, Identifiable {
        public var id: String { ruleID }
        public let ruleID: String
        public let ruleTitle: String
        public var deleted: Int
        public var failed: Int
        public var skipped: Int
        public var cancelled: Int
        public var estimatedBytes: Int64
        public var bytesRemoved: Int64
        public var problems: [String]

        public var status: OverallStatus {
            OverallStatus(deleted: deleted, failed: failed, skipped: skipped, cancelled: cancelled)
        }
    }

    public enum OverallStatus: String, Codable, Sendable {
        case success
        case partial
        case failed
        case cancelled
        case nothingDone

        init(deleted: Int, failed: Int, skipped: Int, cancelled: Int) {
            if failed == 0 && skipped == 0 && cancelled == 0 {
                self = deleted > 0 ? .success : .nothingDone
            } else if cancelled > 0 && failed == 0 {
                self = .cancelled
            } else if deleted > 0 {
                self = .partial
            } else {
                self = .failed
            }
        }
    }

    public let id: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let mode: CleanupPlan.Mode
    public let wasDryRun: Bool
    public let wasCancelled: Bool
    public let items: [ItemOutcome]
    public let rules: [RuleSummary]
    public let estimatedBytesAttempted: Int64
    public let filesystemFreeBytesBefore: Int64?
    public let filesystemFreeBytesAfter: Int64?
    public let messages: [String]

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date, mode: CleanupPlan.Mode, wasDryRun: Bool,
                wasCancelled: Bool, items: [ItemOutcome], rules: [RuleSummary], estimatedBytesAttempted: Int64,
                filesystemFreeBytesBefore: Int64?, filesystemFreeBytesAfter: Int64?, messages: [String]) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode
        self.wasDryRun = wasDryRun
        self.wasCancelled = wasCancelled
        self.items = items
        self.rules = rules
        self.estimatedBytesAttempted = estimatedBytesAttempted
        self.filesystemFreeBytesBefore = filesystemFreeBytesBefore
        self.filesystemFreeBytesAfter = filesystemFreeBytesAfter
        self.messages = messages
    }

    public var attemptedItems: Int { items.filter { $0.status == .deleted || $0.status == .failed }.count }
    public var deletedItems: Int { items.filter { $0.status == .deleted }.count }
    public var failedItems: Int { items.filter { $0.status == .failed }.count }
    public var skippedItems: Int { items.filter { $0.status == .skipped }.count }
    public var cancelledItems: Int { items.filter { $0.status == .cancelled }.count }

    /// Approximate bytes of the files that were removed (sum of per-item measurements).
    public var bytesRemoved: Int64 { items.reduce(0) { $0.saturatingAdd($1.bytesRemoved) } }

    public var overallStatus: OverallStatus {
        OverallStatus(deleted: deletedItems, failed: failedItems, skipped: skippedItems, cancelled: cancelledItems)
    }

    /// Positive change in filesystem free space, if it could be measured. A zero or negative
    /// reading is not reported as reclaimed storage — other processes move this number too.
    public var measuredFreeSpaceChange: Int64? {
        guard let before = filesystemFreeBytesBefore, let after = filesystemFreeBytesAfter, after > before else {
            return nil
        }
        return after - before
    }
}
