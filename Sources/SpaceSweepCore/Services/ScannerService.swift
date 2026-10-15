import Foundation

public struct ScanConfiguration: Sendable {
    public var rules: [CleanupRule]
    public var disabledRuleIDs: Set<String>
    public var runningBundleIDs: Set<String>
    public var now: Date

    public init(rules: [CleanupRule], disabledRuleIDs: Set<String> = [], runningBundleIDs: Set<String> = [], now: Date = Date()) {
        self.rules = rules
        self.disabledRuleIDs = disabledRuleIDs
        self.runningBundleIDs = runningBundleIDs
        self.now = now
    }
}

/// Inspects only the registered rule roots — never the whole disk — and produces an immutable report.
/// Never deletes anything.
public struct ScannerService: Sendable {
    public let environment: PathEnvironment
    public let storage: StorageMeasuring?
    private let validator: PathSafetyValidator
    private let measurer = SizeMeasurer()

    public init(environment: PathEnvironment, storage: StorageMeasuring? = StorageService()) {
        self.environment = environment
        self.storage = storage
        self.validator = PathSafetyValidator(environment: environment)
    }

    private struct Discovered {
        let url: URL
        let status: FileStatus
        let modifiedAt: Date?
    }

    private struct RuleWork {
        let rule: CleanupRule
        let root: URL
        var status: RuleScanStatus
        var rootDevice: UInt64 = 0
        var discovered: [Discovered] = []
        var measurements: [SizeMeasurement] = []
        var skippedLinks = 0
        var skippedOverlaps = 0
    }

    /// Runs a scan. Call from a background task; cancelling that task throws `CancellationError`.
    public func scan(_ configuration: ScanConfiguration, progress: @Sendable (ScanProgress) -> Void) async throws -> ScanReport {
        let startedAt = configuration.now
        var state = ScanProgress(phase: .checkingStorage, totalRules: configuration.rules.count)
        var lastEmit = Date.distantPast
        func emit(force: Bool = false) {
            let now = Date()
            if force || now.timeIntervalSince(lastEmit) > 0.08 {
                lastEmit = now
                progress(state)
            }
        }
        func checkCancelled() throws {
            if Task.isCancelled { throw CancellationError() }
        }

        // 1. Live capacity.
        emit(force: true)
        let volume = try? storage?.snapshot(of: environment.homeDirectory)
        try checkCancelled()

        // 2. Discover candidates under each validated root.
        state.phase = .discovering
        emit(force: true)
        let allRoots = configuration.rules.map { $0.rootURL(in: environment) }
        var work: [RuleWork] = []
        for rule in configuration.rules {
            try checkCancelled()
            state.currentRuleTitle = rule.title
            emit()
            let root = rule.rootURL(in: environment)
            var item = RuleWork(rule: rule, root: root, status: .scanned)
            if configuration.disabledRuleIDs.contains(rule.id) {
                item.status = .disabled
                work.append(item)
                continue
            }
            switch rule.scope {
            case .displayOnlyAggregate:
                discoverAggregate(&item, state: &state)
            case .children:
                try discoverChildren(&item, otherRoots: allRoots.filter { $0 != root }, now: configuration.now, state: &state)
            }
            state.candidatesFound += item.discovered.count
            work.append(item)
        }

        // 3. Measure.
        state.phase = .measuring
        emit(force: true)
        for index in work.indices where work[index].status == .scanned {
            state.currentRuleTitle = work[index].rule.title
            for discovered in work[index].discovered {
                try checkCancelled()
                let measurement = try measurer.measure(discovered.url, device: work[index].rootDevice) { items, bytes in
                    state.examinedItems += items
                    state.measuredBytes = state.measuredBytes.saturatingAdd(bytes)
                    emit()
                    return !Task.isCancelled
                }
                work[index].measurements.append(measurement)
            }
            state.completedRules += 1
            emit()
        }

        // 4. Validate and classify.
        state.phase = .validating
        state.currentRuleTitle = nil
        emit(force: true)
        var claimedPaths = Set<String>()
        var results: [RuleScanResult] = []
        for item in work {
            try checkCancelled()
            guard item.status == .scanned else {
                results.append(RuleScanResult(rule: item.rule, status: item.status))
                continue
            }
            let blockingApps = item.rule.requiresClosedApps.filter { configuration.runningBundleIDs.contains($0.bundleIdentifier) }
            var candidates: [CleanupCandidate] = []
            var unreadable = 0
            var overlaps = item.skippedOverlaps
            for (discovered, measurement) in zip(item.discovered, item.measurements) {
                // Never count the same path twice, even if two rules were to reach it.
                let key = discovered.url.standardizedFileURL.path
                guard claimedPaths.insert(key).inserted else {
                    overlaps += 1
                    continue
                }
                unreadable += measurement.unreadableCount
                // Empty folders free nothing; don't list them as things to clean.
                if item.rule.scope == .children && measurement.bytes == 0 && measurement.fileCount == 0
                    && measurement.unreadableCount == 0 {
                    continue
                }
                candidates.append(classify(discovered, measurement: measurement, rule: item.rule, root: item.root,
                                           blockingApps: blockingApps, running: configuration.runningBundleIDs))
            }
            candidates.sort { $0.estimatedBytes > $1.estimatedBytes }
            results.append(RuleScanResult(rule: item.rule, status: .scanned, candidates: candidates,
                                          blockingApps: blockingApps, skippedSymbolicLinks: item.skippedLinks,
                                          skippedOverlaps: overlaps, unreadableItems: unreadable))
        }

        // 5. Finalise.
        state.phase = .finalising
        emit(force: true)
        try checkCancelled()
        return ScanReport(startedAt: startedAt, finishedAt: Date(), volume: volume, ruleResults: results)
    }

    // MARK: Discovery

    private func discoverAggregate(_ item: inout RuleWork, state: inout ScanProgress) {
        switch FileSystemProbe.lstatus(item.root) {
        case .failure(.notFound):
            item.status = .notFound
        case .failure(.accessDenied):
            item.status = .permissionDenied(mayNeedFullDiskAccess: item.rule.mayNeedFullDiskAccess)
        case .failure(.other):
            item.status = .rootRejected(.rootUnavailable)
        case .success(let status):
            if status.kind == .symbolicLink {
                item.status = .rootRejected(.rootIsSymbolicLink)
                return
            }
            // Confirm the directory is actually readable (privacy protections fail here, not at lstat).
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: item.root.path)
            } catch {
                item.status = Self.status(forListingError: error, rule: item.rule)
                return
            }
            item.rootDevice = status.device
            item.discovered = [Discovered(url: item.root, status: status, modifiedAt: nil)]
            state.examinedItems += 1
        }
    }

    private func discoverChildren(_ item: inout RuleWork, otherRoots: [URL], now: Date, state: inout ScanProgress) throws {
        if validator.isProtected(item.root) {
            item.status = .rootRejected(.protectedLocation)
            return
        }
        switch validator.validateRoot(item.root) {
        case .success(let status):
            item.rootDevice = status.device
        case .failure(.rootUnavailable), .failure(.notADirectoryRoot):
            item.status = .notFound
            return
        case .failure(.accessDenied):
            item.status = .permissionDenied(mayNeedFullDiskAccess: item.rule.mayNeedFullDiskAccess)
            return
        case .failure(let failure):
            item.status = .rootRejected(failure)
            return
        }

        // List names and build each child URL from the root ourselves. (On macOS,
        // `contentsOfDirectory(at:)` may hand back symlink-resolved parents such as /private/var,
        // which would no longer be lexically inside the rule root.)
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(atPath: item.root.path)
                .filter { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }
                .map { item.root.appendingPathComponent($0) }
        } catch {
            item.status = Self.status(forListingError: error, rule: item.rule)
            return
        }

        let cutoff = item.rule.minimumAgeDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if Task.isCancelled { throw CancellationError() }
            state.examinedItems += 1
            let name = child.lastPathComponent
            if item.rule.isChildExcluded(named: name) { continue }
            // Skip anything that contains another rule's root, so nested rules never overlap.
            if otherRoots.contains(where: { PathSafetyValidator.isSameOrInside($0, child) }) {
                item.skippedOverlaps += 1
                continue
            }
            guard case .success(let status) = FileSystemProbe.lstatus(child) else { continue }
            if status.kind == .symbolicLink {
                item.skippedLinks += 1
                continue
            }
            let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let cutoff {
                guard let modified, modified <= cutoff else { continue }
            }
            item.discovered.append(Discovered(url: child, status: status, modifiedAt: modified))
        }
    }

    static func status(forListingError error: Error, rule: CleanupRule) -> RuleScanStatus {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let posix = nsError.domain == NSPOSIXErrorDomain ? nsError.code : (underlying?.domain == NSPOSIXErrorDomain ? underlying?.code : nil)
        if posix == Int(EPERM) {
            // EPERM on a directory you own is how macOS privacy protections (TCC) report a denial.
            return .permissionDenied(mayNeedFullDiskAccess: true)
        }
        if posix == Int(EACCES) || nsError.code == CocoaError.fileReadNoPermission.rawValue {
            return .permissionDenied(mayNeedFullDiskAccess: rule.mayNeedFullDiskAccess)
        }
        if nsError.code == CocoaError.fileReadNoSuchFile.rawValue || posix == Int(ENOENT) {
            return .notFound
        }
        return .rootRejected(.rootUnavailable)
    }

    // MARK: Classification

    private func classify(_ discovered: Discovered, measurement: SizeMeasurement, rule: CleanupRule, root: URL,
                          blockingApps: [KnownApp], running: Set<String>) -> CleanupCandidate {
        let name = discovered.url.lastPathComponent
        var tier = rule.tier
        var blockedReason: String?
        var fingerprint: CandidateFingerprint?

        if rule.scope == .displayOnlyAggregate || !rule.isDeletable {
            tier = .protected
            blockedReason = nil
        } else {
            switch validator.validate(target: discovered.url, root: root, expected: CandidateFingerprint(discovered.status)) {
            case .success(let value):
                fingerprint = value
                if !blockingApps.isEmpty {
                    tier = .blocked
                    blockedReason = Self.quitMessage(for: blockingApps)
                } else if rule.blocksChildrenNamedAfterRunningApps, running.contains(name) {
                    tier = .blocked
                    blockedReason = "The app that owns this cache is running. Quit it, then rescan."
                }
            case .failure(let failure):
                tier = failure == .protectedLocation ? .protected : .blocked
                blockedReason = failure.userMessage
            }
        }

        let displayName = rule.scope == .displayOnlyAggregate ? rule.title : PathDisplay.friendlyName(for: name, ruleID: rule.id)
        return CleanupCandidate(
            ruleID: rule.id,
            url: discovered.url,
            rootURL: root,
            displayName: displayName,
            displayPath: PathDisplay.shortened(discovered.url, home: environment.homeDirectory),
            estimatedBytes: measurement.bytes,
            itemCount: max(measurement.fileCount, 0),
            modifiedAt: discovered.modifiedAt,
            tier: tier,
            blockedReason: blockedReason,
            fingerprint: tier.isDeletableTier ? fingerprint : nil,
            isSelectedByDefault: rule.defaultSelected && tier == .safe,
            sizeIsPartial: measurement.unreadableCount > 0
        )
    }

    public static func quitMessage(for apps: [KnownApp]) -> String {
        let names = apps.map(\.displayName)
        let list: String
        switch names.count {
        case 0: return ""
        case 1: list = names[0]
        default: list = names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
        return "Quit \(list) to clean this."
    }
}
