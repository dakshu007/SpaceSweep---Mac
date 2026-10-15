import Foundation

/// The only component that removes files. Abstracted so tests can simulate failures.
public protocol FileRemoving: Sendable {
    func removeItem(at url: URL) throws
}

/// Uses `FileManager.removeItem(at:)`, which removes symbolic links themselves rather than following them.
/// No shell commands are ever run.
public struct FoundationFileRemover: FileRemoving {
    public init() {}
    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

public struct CleanupProgress: Sendable, Equatable {
    public var completedTargets: Int
    public var totalTargets: Int
    public var currentRuleID: String?
    public var currentRuleTitle: String?
    public var currentItemName: String?
    public var bytesRemoved: Int64
    public var deleted: Int
    public var failed: Int
    public var skipped: Int

    public init(completedTargets: Int, totalTargets: Int, currentRuleID: String? = nil, currentRuleTitle: String? = nil,
                currentItemName: String? = nil, bytesRemoved: Int64 = 0, deleted: Int = 0, failed: Int = 0, skipped: Int = 0) {
        self.completedTargets = completedTargets
        self.totalTargets = totalTargets
        self.currentRuleID = currentRuleID
        self.currentRuleTitle = currentRuleTitle
        self.currentItemName = currentItemName
        self.bytesRemoved = bytesRemoved
        self.deleted = deleted
        self.failed = failed
        self.skipped = skipped
    }

    public var fraction: Double {
        totalTargets == 0 ? 0 : Double(completedTargets) / Double(totalTargets)
    }
}

/// Executes a confirmed `CleanupPlan`, one target at a time, revalidating every target immediately
/// before it is removed. Errors are recorded honestly and never reported as success.
public struct CleanupExecutor: Sendable {
    public let registry: CleanupRuleRegistry
    public let environment: PathEnvironment
    public let storage: StorageMeasuring?
    public let remover: FileRemoving
    public let applications: RunningApplicationsProviding
    /// When true, everything is validated and measured but nothing is removed.
    public let dryRun: Bool

    private let validator: PathSafetyValidator
    private let measurer = SizeMeasurer()

    public init(registry: CleanupRuleRegistry = .standard, environment: PathEnvironment,
                storage: StorageMeasuring? = StorageService(), remover: FileRemoving = FoundationFileRemover(),
                applications: RunningApplicationsProviding, dryRun: Bool = false) {
        self.registry = registry
        self.environment = environment
        self.storage = storage
        self.remover = remover
        self.applications = applications
        self.dryRun = dryRun
        self.validator = PathSafetyValidator(environment: environment)
    }

    public func execute(_ plan: CleanupPlan, progress: @Sendable (CleanupProgress) -> Void = { _ in }) async -> CleanupReport {
        let startedAt = Date()
        var outcomes: [CleanupReport.ItemOutcome] = []
        var messages: [String] = []
        var state = CleanupProgress(completedTargets: 0, totalTargets: plan.targets.count, bytesRemoved: 0,
                                    deleted: 0, failed: 0, skipped: 0)

        func record(_ target: PlannedTarget, _ status: CleanupReport.ItemStatus, removed: Int64 = 0, _ message: String? = nil) {
            outcomes.append(.init(id: target.id, ruleID: target.ruleID, ruleTitle: target.ruleTitle,
                                  displayName: target.displayName, displayPath: target.displayPath, status: status,
                                  estimatedBytes: target.estimatedBytes, bytesRemoved: removed, message: message))
            switch status {
            case .deleted: state.deleted += 1
            case .failed: state.failed += 1
            case .skipped, .cancelled: state.skipped += 1
            }
            state.bytesRemoved = state.bytesRemoved.saturatingAdd(removed)
            state.completedTargets += 1
            progress(state)
        }

        // Gate 1: the plan must be authorised.
        let authorised: Bool
        switch plan.authorization {
        case .pendingConfirmation:
            authorised = false
            messages.append("The cleanup plan was not confirmed, so nothing was removed.")
        case .userConfirmed:
            authorised = true
        case .oneClickPreference:
            authorised = plan.mode == .oneClickSafe
            if !authorised { messages.append("One-click authorisation is only valid for Safe-only plans.") }
        }

        let freeBefore = authorised && !dryRun ? storage?.freeBytes(of: environment.homeDirectory) : nil
        var running = await applications.runningBundleIdentifiers()
        var lastRuleID: String?
        var cancelled = false

        for target in plan.targets {
            guard authorised else {
                record(target, .skipped, "Plan not confirmed.")
                continue
            }
            if cancelled || Task.isCancelled {
                cancelled = true
                record(target, .cancelled, "Cancelled before this item started.")
                continue
            }
            state.currentRuleID = target.ruleID
            state.currentRuleTitle = target.ruleTitle
            state.currentItemName = target.displayName
            progress(state)

            // Re-check app state whenever we move on to a new rule.
            if lastRuleID != target.ruleID {
                running = await applications.runningBundleIdentifiers()
                lastRuleID = target.ruleID
            }

            // Gate 2: the rule must exist, be deletable and match the planned tier.
            guard let rule = registry.rule(id: target.ruleID), rule.isDeletable, rule.tier == target.tier else {
                record(target, .skipped, "This item no longer matches a known cleanup rule.")
                continue
            }
            if plan.mode == .oneClickSafe && (rule.tier != .safe || rule.removesUserFilesPermanently) {
                record(target, .skipped, "Review items are never cleaned by One-click Safe Clean.")
                continue
            }
            if plan.authorization == .oneClickPreference && target.tier != .safe {
                record(target, .skipped, "Review items are never cleaned by One-click Safe Clean.")
                continue
            }
            // Gate 3: the target must still sit under the rule's own root.
            let root = rule.rootURL(in: environment)
            guard root.standardizedFileURL.path == target.rootURL.standardizedFileURL.path else {
                record(target, .skipped, ValidationFailure.notInsideRoot.userMessage)
                continue
            }
            // Gate 4: required apps must be closed.
            let blocking = rule.requiresClosedApps.filter { running.contains($0.bundleIdentifier) }
            if !blocking.isEmpty {
                record(target, .skipped, ScannerService.quitMessage(for: blocking))
                continue
            }
            if rule.blocksChildrenNamedAfterRunningApps && running.contains(target.url.lastPathComponent) {
                record(target, .skipped, "The app that owns this cache is running.")
                continue
            }
            // Gate 5: full path validation against the scanned fingerprint.
            let fingerprint: CandidateFingerprint
            switch validator.validate(target: target.url, root: root, expected: target.fingerprint) {
            case .success(let value): fingerprint = value
            case .failure(let failure):
                record(target, .skipped, failure.userMessage)
                continue
            }

            // Measure what is actually there right now.
            let before: SizeMeasurement
            do {
                before = try measurer.measure(target.url, device: fingerprint.device) { _, _ in !Task.isCancelled }
            } catch {
                cancelled = true
                record(target, .cancelled, "Cancelled before this item was removed.")
                continue
            }

            if dryRun {
                record(target, .skipped, "Dry run — nothing removed.")
                continue
            }

            do {
                try remover.removeItem(at: target.url)
                record(target, .deleted, removed: before.bytes)
            } catch {
                // Report how much (if anything) was actually removed before the failure.
                var removed: Int64 = 0
                if case .success = FileSystemProbe.lstatus(target.url),
                   let remaining = try? measurer.measure(target.url, device: fingerprint.device, tick: { _, _ in true }) {
                    removed = max(0, before.bytes - remaining.bytes)
                } else if case .failure(.notFound) = FileSystemProbe.lstatus(target.url) {
                    removed = before.bytes
                }
                record(target, .failed, removed: removed, Self.describe(error))
            }
        }

        let freeAfter = authorised && !dryRun ? storage?.freeBytes(of: environment.homeDirectory) : nil
        if cancelled { messages.append("Cleanup was cancelled. Items that hadn’t started were left untouched.") }

        return CleanupReport(
            startedAt: startedAt,
            finishedAt: Date(),
            mode: plan.mode,
            wasDryRun: dryRun,
            wasCancelled: cancelled,
            items: outcomes,
            rules: Self.summaries(from: outcomes),
            estimatedBytesAttempted: plan.estimatedBytes,
            filesystemFreeBytesBefore: freeBefore,
            filesystemFreeBytesAfter: freeAfter,
            messages: messages
        )
    }

    static func summaries(from outcomes: [CleanupReport.ItemOutcome]) -> [CleanupReport.RuleSummary] {
        var order: [String] = []
        var map: [String: CleanupReport.RuleSummary] = [:]
        for outcome in outcomes {
            if map[outcome.ruleID] == nil {
                order.append(outcome.ruleID)
                map[outcome.ruleID] = .init(ruleID: outcome.ruleID, ruleTitle: outcome.ruleTitle, deleted: 0, failed: 0,
                                            skipped: 0, cancelled: 0, estimatedBytes: 0, bytesRemoved: 0, problems: [])
            }
            var summary = map[outcome.ruleID]!
            switch outcome.status {
            case .deleted: summary.deleted += 1
            case .failed: summary.failed += 1
            case .skipped: summary.skipped += 1
            case .cancelled: summary.cancelled += 1
            }
            summary.estimatedBytes = summary.estimatedBytes.saturatingAdd(outcome.estimatedBytes)
            summary.bytesRemoved = summary.bytesRemoved.saturatingAdd(outcome.bytesRemoved)
            if let message = outcome.message, outcome.status != .deleted, !summary.problems.contains(message) {
                summary.problems.append(message)
            }
            map[outcome.ruleID] = summary
        }
        return order.compactMap { map[$0] }
    }

    /// Maps a removal error to an understandable category without leaking paths.
    public static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let posixCode: Int? = nsError.domain == NSPOSIXErrorDomain ? nsError.code
            : (underlying?.domain == NSPOSIXErrorDomain ? underlying?.code : nil)
        switch posixCode.map(Int32.init) {
        case EPERM: return "Operation not permitted — macOS security protections blocked the removal."
        case EACCES: return "Permission denied by file ownership or access controls."
        case EBUSY, ETXTBSY: return "The item is in use."
        case ENOENT: return "The item disappeared during cleanup."
        case ENOSPC: return "The disk is full."
        case EROFS: return "The volume is read-only."
        case ENOTEMPTY: return "Some contents could not be removed."
        default: break
        }
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileReadNoPermission.rawValue:
                return "Permission denied."
            case CocoaError.fileNoSuchFile.rawValue:
                return "The item disappeared during cleanup."
            case CocoaError.fileWriteVolumeReadOnly.rawValue:
                return "The volume is read-only."
            case CocoaError.fileWriteOutOfSpace.rawValue:
                return "The disk is full."
            default: break
            }
        }
        return "The item could not be removed (error \(nsError.code))."
    }
}
