import AppKit
import Observation
import OSLog
import SpaceSweepCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case results
    case developer
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .results: return "Scan Results"
        case .developer: return "Developer Cleanup"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .results: return "list.bullet.rectangle.portrait"
        case .developer: return "hammer"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .results: return "2"
        case .developer: return "3"
        case .activity: return "4"
        case .settings: return "5"
        }
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ScanState: Equatable {
    case idle
    case scanning(ScanProgress)
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

enum CleanupFlow {
    case confirming(CleanupPlan)
    case running(CleanupPlan, CleanupProgress)
    case finished(CleanupReport)
}

/// App-wide state. All file-system work happens off the main actor in core services.
@MainActor
@Observable
final class AppModel {
    // MARK: Dependencies
    let environment = PathEnvironment.live
    let registry = CleanupRuleRegistry.standard
    let storage = StorageService()
    let applications = WorkspaceRunningApplications()
    let permissions = PermissionService()
    let activityLog = ActivityLogService(fileURL: ActivityLogService.defaultFileURL())
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Local diagnostics only. Never includes paths or file names.
    @ObservationIgnored private let logger = Logger(subsystem: "app.spacesweep.mac", category: "activity")

    // MARK: State
    var route: SidebarItem = .overview
    var volume: VolumeSnapshot?
    var volumeUnavailable = false
    var scanState: ScanState = .idle
    var report: ScanReport?
    var selection: Set<UUID> = []
    var cleanupFlow: CleanupFlow?
    var lastCleanup: CleanupReport?
    var activity: [ActivityEntry] = []
    var fullDiskAccess: FullDiskAccessStatus = .unknown
    var runningBundleIDs: Set<String> = []
    var notice: Notice?
    /// Bumped every 30 s so time-based UI (scan age, plan expiry) refreshes.
    var clock = Date()

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        var offersRescan = false
    }

    // MARK: Preferences
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); applyAppearance() }
    }
    var oneClickEnabled: Bool {
        didSet { defaults.set(oneClickEnabled, forKey: Keys.oneClick) }
    }
    var hasConfirmedFirstClean: Bool {
        didSet { defaults.set(hasConfirmedFirstClean, forKey: Keys.firstClean) }
    }
    var disabledRuleIDs: Set<String> {
        didSet { defaults.set(Array(disabledRuleIDs).sorted(), forKey: Keys.disabledRules) }
    }
    var recordPathsInActivity: Bool {
        didSet { defaults.set(recordPathsInActivity, forKey: Keys.recordPaths) }
    }
    private(set) var lastScanDate: Date? {
        didSet { defaults.set(lastScanDate, forKey: Keys.lastScan) }
    }

    private enum Keys {
        static let appearance = "appearance"
        static let oneClick = "oneClickSafeClean"
        static let firstClean = "hasConfirmedFirstClean"
        static let disabledRules = "disabledRuleIDs"
        static let recordPaths = "recordPathsInActivity"
        static let lastScan = "lastScanDate"
    }

    @ObservationIgnored private var scanWorker: Task<ScanReport, Error>?
    @ObservationIgnored private var scanToken = UUID()
    @ObservationIgnored private var cleanupWorker: Task<CleanupReport, Never>?
    @ObservationIgnored private var oneClickAfterScan = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        oneClickEnabled = defaults.bool(forKey: Keys.oneClick)
        hasConfirmedFirstClean = defaults.bool(forKey: Keys.firstClean)
        disabledRuleIDs = Set(defaults.stringArray(forKey: Keys.disabledRules) ?? [])
        recordPathsInActivity = defaults.bool(forKey: Keys.recordPaths)
        lastScanDate = defaults.object(forKey: Keys.lastScan) as? Date
        activity = activityLog.load()
        fullDiskAccess = permissions.fullDiskAccessStatus()
        refreshVolume()
        observeWorkspace()
        startTicker()
    }

    // MARK: Derived

    var isScanning: Bool { scanState.isScanning }
    var isCleaning: Bool {
        if case .running = cleanupFlow { return true }
        return false
    }

    var reportIsStale: Bool {
        guard let report else { return false }
        return clock.timeIntervalSince(report.finishedAt) > CleanupPlanner.maximumScanAge
            || Date().timeIntervalSince(report.finishedAt) > CleanupPlanner.maximumScanAge
    }

    var selectedCandidates: [CleanupCandidate] {
        guard let report else { return [] }
        return report.allCandidates.filter { selection.contains($0.id) && $0.isSelectable }
    }

    var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0.saturatingAdd($1.estimatedBytes) } }
    var selectionIncludesReview: Bool { selectedCandidates.contains { $0.tier == .review } }

    var canOneClick: Bool { oneClickEnabled && hasConfirmedFirstClean }

    func isRunning(_ app: KnownApp) -> Bool { runningBundleIDs.contains(app.bundleIdentifier) }

    // MARK: Storage

    func refreshVolume() {
        let storage = storage
        let home = environment.homeDirectory
        Task.detached(priority: .utility) {
            let snapshot = try? storage.snapshot(of: home)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let snapshot {
                    self.volume = snapshot
                    self.volumeUnavailable = false
                } else {
                    self.volumeUnavailable = true
                }
            }
        }
    }

    func refreshPermissions() {
        fullDiskAccess = permissions.fullDiskAccessStatus()
    }

    // MARK: Scanning

    func startScan() {
        guard !isScanning, !isCleaning else { return }
        let token = UUID()
        scanToken = token
        scanState = .scanning(ScanProgress(phase: .checkingStorage, totalRules: registry.rules.count))
        refreshPermissions()

        let rules = registry.rules
        let disabled = disabledRuleIDs
        let environment = environment
        let storage = storage
        let applications = applications

        let worker = Task.detached(priority: .userInitiated) { () throws -> ScanReport in
            let running = await applications.runningBundleIdentifiers()
            let configuration = ScanConfiguration(rules: rules, disabledRuleIDs: disabled, runningBundleIDs: running)
            let scanner = ScannerService(environment: environment, storage: storage)
            return try await scanner.scan(configuration) { progress in
                Task { @MainActor [weak self] in self?.updateScan(progress, token: token) }
            }
        }
        scanWorker = worker

        Task { [weak self] in
            do {
                let report = try await worker.value
                self?.finishScan(report, token: token)
            } catch is CancellationError {
                self?.scanEnded(token: token, state: .idle)
            } catch {
                self?.scanEnded(token: token, state: .failed("The scan could not be completed."))
            }
        }
    }

    func cancelScan() {
        oneClickAfterScan = false
        scanWorker?.cancel()
    }

    private func updateScan(_ progress: ScanProgress, token: UUID) {
        guard token == scanToken, isScanning else { return }
        scanState = .scanning(progress)
    }

    private func scanEnded(token: UUID, state: ScanState) {
        guard token == scanToken else { return }
        scanWorker = nil
        oneClickAfterScan = false
        withAnimation(.snappy) { scanState = state }
    }

    private func finishScan(_ newReport: ScanReport, token: UUID) {
        guard token == scanToken else { return }
        scanWorker = nil
        withAnimation(.snappy) {
            report = newReport
            selection = newReport.defaultSelection
            scanState = .idle
        }
        lastScanDate = newReport.finishedAt
        clock = Date()
        let scanned = newReport.ruleResults.filter { $0.status == .scanned }.count
        logger.notice("Scan finished: \(scanned, privacy: .public) of \(newReport.ruleResults.count, privacy: .public) rules scanned; safe \(newReport.count(in: .safe), privacy: .public) items / \(newReport.bytes(in: .safe), privacy: .public) bytes; review \(newReport.count(in: .review), privacy: .public) items / \(newReport.bytes(in: .review), privacy: .public) bytes; blocked \(newReport.count(in: .blocked), privacy: .public); protected \(newReport.count(in: .protected), privacy: .public); partial \(newReport.isPartial, privacy: .public)")
        if let snapshot = newReport.volume { volume = snapshot }
        appendActivity(.from(scan: newReport))

        if oneClickAfterScan {
            oneClickAfterScan = false
            performOneClickClean(using: newReport)
        }
    }

    func clearScanResults() {
        report = nil
        selection = []
        lastScanDate = nil
    }

    // MARK: Selection

    func toggle(_ candidate: CleanupCandidate) {
        guard candidate.isSelectable else { return }
        if selection.contains(candidate.id) { selection.remove(candidate.id) } else { selection.insert(candidate.id) }
    }

    func selectionState(for result: RuleScanResult) -> TriStateCheckbox.CheckState {
        let selectable = result.candidates.filter(\.isSelectable)
        guard !selectable.isEmpty else { return .off }
        let count = selectable.filter { selection.contains($0.id) }.count
        if count == 0 { return .off }
        return count == selectable.count ? .on : .mixed
    }

    func toggleAll(in result: RuleScanResult) {
        let ids = result.candidates.filter(\.isSelectable).map(\.id)
        if selectionState(for: result) == .on {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func resetSelectionToSafeDefaults() {
        selection = report?.defaultSelection ?? []
    }

    // MARK: Cleanup

    /// Review & clean the current selection. Always shows the confirmation summary.
    func beginCleanup() {
        guard let report, !isCleaning else { return }
        do {
            let plan = try CleanupPlanner(registry: registry).makePlan(from: report, selectedIDs: selection)
            cleanupFlow = .confirming(plan)
        } catch let error as PlanError {
            notice = Notice(title: error == .scanExpired ? "Results are out of date" : "Nothing to clean",
                            message: error.userMessage, offersRescan: error == .scanExpired)
        } catch {
            notice = Notice(title: "Couldn’t prepare cleanup", message: "Please rescan and try again.", offersRescan: true)
        }
    }

    /// One-click Safe Clean: scan, then clean the fixed Safe tier only, without a second confirmation.
    /// Falls back to the normal review flow until the user has opted in and confirmed a first cleanup.
    func oneClickSafeClean() {
        guard canOneClick else {
            if report == nil || reportIsStale { startScan() } else { route = .results }
            return
        }
        oneClickAfterScan = true
        startScan()
    }

    private func performOneClickClean(using report: ScanReport) {
        do {
            let plan = try CleanupPlanner(registry: registry).makeOneClickPlan(from: report)
            guard let authorised = plan.authorizedByOneClickPreference() else {
                cleanupFlow = .confirming(plan)
                return
            }
            run(authorised)
        } catch {
            notice = Notice(title: "Nothing safe to clean",
                            message: "The scan didn’t find any Safe items right now. Review items are never cleaned automatically — open Scan Results to review them.")
        }
    }

    func confirm(_ plan: CleanupPlan) {
        hasConfirmedFirstClean = true
        run(plan.confirmedByUser())
    }

    func dismissCleanupFlow() {
        guard !isCleaning else { return }
        cleanupFlow = nil
    }

    private func run(_ plan: CleanupPlan) {
        cleanupFlow = .running(plan, CleanupProgress(completedTargets: 0, totalTargets: plan.targets.count,
                                                     bytesRemoved: 0, deleted: 0, failed: 0, skipped: 0))
        let executor = CleanupExecutor(registry: registry, environment: environment, storage: storage,
                                       applications: applications)
        let planID = plan.id
        let worker = Task.detached(priority: .userInitiated) { () -> CleanupReport in
            await executor.execute(plan) { progress in
                Task { @MainActor [weak self] in self?.updateCleanup(progress, planID: planID) }
            }
        }
        cleanupWorker = worker
        Task { [weak self] in
            let report = await worker.value
            self?.finishCleanup(report)
        }
    }

    func cancelCleanup() {
        cleanupWorker?.cancel()
    }

    private func updateCleanup(_ progress: CleanupProgress, planID: UUID) {
        guard case .running(let plan, _) = cleanupFlow, plan.id == planID else { return }
        cleanupFlow = .running(plan, progress)
    }

    private func finishCleanup(_ cleanup: CleanupReport) {
        cleanupWorker = nil
        logger.notice("Cleanup finished: \(cleanup.deletedItems, privacy: .public) removed, \(cleanup.failedItems, privacy: .public) failed, \(cleanup.skippedItems, privacy: .public) skipped, \(cleanup.cancelledItems, privacy: .public) cancelled")
        lastCleanup = cleanup
        withAnimation(.snappy) { cleanupFlow = .finished(cleanup) }
        appendActivity(.from(cleanup: cleanup, includePaths: recordPathsInActivity))
        // Results no longer describe the disk; require a fresh scan before the next cleanup.
        report = nil
        selection = []
        refreshVolume()
    }

    // MARK: Activity

    private func appendActivity(_ entry: ActivityEntry) {
        do {
            activity = try activityLog.append(entry)
        } catch {
            activity.insert(entry, at: 0)
        }
    }

    func clearActivity() {
        try? activityLog.clear()
        activity = []
    }

    // MARK: Rules

    func isRuleEnabled(_ rule: CleanupRule) -> Bool { !disabledRuleIDs.contains(rule.id) }

    func setRule(_ rule: CleanupRule, enabled: Bool) {
        if enabled { disabledRuleIDs.remove(rule.id) } else { disabledRuleIDs.insert(rule.id) }
        // Rules changed: existing results are no longer a valid basis for a plan.
        if report != nil {
            clearScanResults()
            notice = Notice(title: "Rules changed", message: "Scan again to see results with your updated rules.", offersRescan: true)
        }
    }

    // MARK: Environment

    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(PermissionService.fullDiskAccessSettingsURL)
    }

    /// Opens the rule's folder (never the item itself) in Finder, when it is a real directory.
    func revealRoot(of rule: CleanupRule) {
        let root = rule.rootURL(in: environment)
        guard case .success(let status) = FileSystemProbe.lstatus(root), status.kind == .directory else { return }
        NSWorkspace.shared.open(root)
    }

    func rootExists(_ rule: CleanupRule) -> Bool {
        if case .success(let status) = FileSystemProbe.lstatus(rule.rootURL(in: environment)) {
            return status.kind == .directory
        }
        return false
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let update: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refreshRunningApps() }
        }
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: update))
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: update))
        refreshRunningApps()
    }

    private func refreshRunningApps() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.clock = Date()
                if !self.isCleaning { self.refreshVolume() }
            }
        }
    }

    /// Developer conveniences for demos and smoke tests (e.g. `-SpaceSweepAutoScan YES`).
    /// A scan never deletes anything, so these are safe.
    func applyLaunchOptions() {
        if let raw = defaults.string(forKey: "SpaceSweepInitialRoute"), let item = SidebarItem(rawValue: raw) {
            route = item
        }
        if defaults.bool(forKey: "SpaceSweepAutoScan") { startScan() }
    }

    // MARK: App info

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "\(version) (\(build))"
    }
}
