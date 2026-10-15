import Foundation

/// A local-only record of what SpaceSweep did. By default no file paths are stored.
public struct ActivityEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case scan
        case cleanup
        case dryRun
    }

    public enum Status: String, Codable, Sendable {
        case success
        case partial
        case failed
        case cancelled
        case info
    }

    public struct RuleLine: Codable, Sendable, Equatable, Identifiable {
        public var id: String { ruleID }
        public let ruleID: String
        public let title: String
        public let deleted: Int
        public let failed: Int
        public let skipped: Int
        public let estimatedBytes: Int64
        public let bytesRemoved: Int64
        public let problems: [String]
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let status: Status
    public let title: String
    public let detail: String
    public let estimatedBytes: Int64
    public let bytesRemoved: Int64
    public let measuredFreeSpaceChange: Int64?
    public let rules: [RuleLine]
    /// Only populated when the user opted in to recording paths.
    public let paths: [String]?

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, status: Status, title: String, detail: String,
                estimatedBytes: Int64 = 0, bytesRemoved: Int64 = 0, measuredFreeSpaceChange: Int64? = nil,
                rules: [RuleLine] = [], paths: [String]? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.estimatedBytes = estimatedBytes
        self.bytesRemoved = bytesRemoved
        self.measuredFreeSpaceChange = measuredFreeSpaceChange
        self.rules = rules
        self.paths = paths
    }

    public static func from(cleanup report: CleanupReport, includePaths: Bool) -> ActivityEntry {
        let status: Status
        switch report.overallStatus {
        case .success: status = .success
        case .partial: status = .partial
        case .failed: status = .failed
        case .cancelled: status = .cancelled
        case .nothingDone: status = .info
        }
        let title: String
        if report.wasDryRun {
            title = "Dry run"
        } else {
            title = report.mode == .oneClickSafe ? "One-click Safe Clean" : "Cleanup"
        }
        let detail = "\(report.deletedItems) removed · \(report.failedItems) failed · \(report.skippedItems) skipped"
            + (report.cancelledItems > 0 ? " · \(report.cancelledItems) cancelled" : "")
        let lines = report.rules.map {
            RuleLine(ruleID: $0.ruleID, title: $0.ruleTitle, deleted: $0.deleted, failed: $0.failed,
                     skipped: $0.skipped + $0.cancelled, estimatedBytes: $0.estimatedBytes,
                     bytesRemoved: $0.bytesRemoved, problems: $0.problems)
        }
        let paths = includePaths ? report.items.filter { $0.status != .deleted }.map(\.displayPath) : nil
        return ActivityEntry(date: report.finishedAt, kind: report.wasDryRun ? .dryRun : .cleanup, status: status,
                             title: title, detail: detail, estimatedBytes: report.estimatedBytesAttempted,
                             bytesRemoved: report.bytesRemoved, measuredFreeSpaceChange: report.measuredFreeSpaceChange,
                             rules: lines, paths: paths)
    }

    public static func from(scan report: ScanReport) -> ActivityEntry {
        let found = report.allCandidates.count
        return ActivityEntry(
            date: report.finishedAt,
            kind: .scan,
            status: report.isPartial ? .partial : .success,
            title: report.isPartial ? "Scan (partial)" : "Scan",
            detail: "\(found) item\(found == 1 ? "" : "s") found across \(report.ruleResults.filter { !$0.candidates.isEmpty }.count) categories",
            estimatedBytes: report.bytes(in: .safe).saturatingAdd(report.bytes(in: .review))
        )
    }
}

/// Stores activity as JSON in SpaceSweep's own Application Support folder. Never uploaded.
public final class ActivityLogService: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    public static let maximumEntries = 500

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SpaceSweep", isDirectory: true).appendingPathComponent("activity.json")
    }

    public func load() -> [ActivityEntry] {
        lock.lock(); defer { lock.unlock() }
        return unlockedLoad()
    }

    private func unlockedLoad() -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ActivityEntry].self, from: data)) ?? []
    }

    @discardableResult
    public func append(_ entry: ActivityEntry) throws -> [ActivityEntry] {
        lock.lock(); defer { lock.unlock() }
        var entries = unlockedLoad()
        entries.insert(entry, at: 0)
        if entries.count > Self.maximumEntries { entries.removeLast(entries.count - Self.maximumEntries) }
        try write(entries)
        return entries
    }

    /// Clears SpaceSweep's own history file. Never touches cleanup targets.
    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try write([])
    }

    private func write(_ entries: [ActivityEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }

    /// Plain-text diagnostic export. Paths are included only when explicitly requested.
    public static func exportText(_ entries: [ActivityEntry], includePaths: Bool, appVersion: String) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["SpaceSweep activity export", "Version: \(appVersion)", "Exported: \(formatter.string(from: Date()))",
                     "Paths included: \(includePaths ? "yes" : "no")", ""]
        for entry in entries {
            lines.append("[\(formatter.string(from: entry.date))] \(entry.title) — \(entry.status.rawValue)")
            lines.append("  \(entry.detail)")
            lines.append("  estimated bytes: \(entry.estimatedBytes), bytes removed (approx.): \(entry.bytesRemoved), measured free-space change: \(entry.measuredFreeSpaceChange.map(String.init) ?? "not measured")")
            for rule in entry.rules {
                lines.append("  • \(rule.ruleID): removed \(rule.deleted), failed \(rule.failed), skipped \(rule.skipped), bytes removed \(rule.bytesRemoved)")
                for problem in rule.problems { lines.append("      – \(problem)") }
            }
            if includePaths, let paths = entry.paths, !paths.isEmpty {
                lines.append("  paths not removed:")
                for path in paths { lines.append("      \(path)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
