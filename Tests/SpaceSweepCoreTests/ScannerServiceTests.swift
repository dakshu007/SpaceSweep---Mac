import XCTest
@testable import SpaceSweepCore

final class ScannerServiceTests: XCTestCase {
    typealias ID = CleanupRuleRegistry.ID
    var fixture: Fixture!

    override func setUpWithError() throws { fixture = try Fixture() }
    override func tearDown() { fixture = nil }

    func testDerivedDataChildrenAreSafeAndSelected() async throws {
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "Build", "a.o", bytes: 100_000)
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-b", "Index", "b.idx", bytes: 50_000)
        let report = try await fixture.scan()
        let result = try XCTUnwrap(report.result(for: ID.xcodeDerivedData))
        XCTAssertEqual(result.status, .scanned)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertTrue(result.candidates.allSatisfy { $0.tier == .safe && $0.isSelectable && $0.isSelectedByDefault })
        XCTAssertGreaterThanOrEqual(result.totalBytes, 150_000)
        XCTAssertEqual(result.candidates.first?.displayName, "App-a")
        XCTAssertTrue(result.candidates.allSatisfy { $0.displayPath.hasPrefix("~/Library/Developer/Xcode/DerivedData/") })
        // Root is never a candidate.
        XCTAssertFalse(result.candidates.contains { $0.url.standardizedFileURL == fixture.root(of: ID.xcodeDerivedData).standardizedFileURL })
        XCTAssertEqual(report.defaultSelection.count, 2)
    }

    // 10 (scan side)
    func testRunningXcodeBlocksDerivedData() async throws {
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "x", bytes: 1000)
        let report = try await fixture.scan(running: [KnownApp.xcode.bundleIdentifier])
        let result = try XCTUnwrap(report.result(for: ID.xcodeDerivedData))
        XCTAssertEqual(result.blockingApps, [.xcode])
        XCTAssertTrue(result.candidates.allSatisfy { $0.tier == .blocked && !$0.isSelectable && !$0.isSelectedByDefault })
        XCTAssertEqual(result.candidates.first?.blockedReason, "Quit Xcode to clean this.")
        XCTAssertTrue(report.defaultSelection.isEmpty)
    }

    func testSymlinksAreSkippedAndNeverFollowed() async throws {
        try fixture.file("huge.bin", bytes: 2_000_000, from: fixture.outside)
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "x", bytes: 1000)
        try fixture.symlink("Library", "Developer", "Xcode", "DerivedData", "LinkToOutside", to: fixture.outside)
        try fixture.symlink("Library", "Developer", "Xcode", "DerivedData", "App-a", "nested-link", to: fixture.outside)
        let report = try await fixture.scan()
        let result = try XCTUnwrap(report.result(for: ID.xcodeDerivedData))
        XCTAssertEqual(result.candidates.map(\.displayName), ["App-a"])
        XCTAssertEqual(result.skippedSymbolicLinks, 1)
        XCTAssertLessThan(result.totalBytes, 1_000_000, "symlinked content must not be measured")
    }

    // 6
    func testUnknownCacheIsReviewNeverSafe() async throws {
        try fixture.file("Library", "Caches", "com.example.SomeApp", "blob", bytes: 10_000)
        try fixture.file("Library", "Caches", "com.apple.Safari", "blob", bytes: 10_000)
        let report = try await fixture.scan()
        let all = report.allCandidates.filter { $0.displayName == "com.example.SomeApp" }
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.tier, .review)
        XCTAssertEqual(all.first?.isSelectedByDefault, false)
        XCTAssertFalse(report.allCandidates.contains { $0.displayName.hasPrefix("com.apple.") })
    }

    // 13
    func testNestedRulesDoNotDoubleCount() async throws {
        try fixture.file("Library", "Caches", "Yarn", "v6", "pkg.tgz", bytes: 30_000)
        try fixture.file("Library", "Caches", "Homebrew", "downloads", "bottle.tar.gz", bytes: 20_000)
        try fixture.file("Library", "Caches", "Google", "Chrome", "Default", "Cache", "data", bytes: 5_000)
        let report = try await fixture.scan()
        let yarnHits = report.allCandidates.filter { $0.url.path.contains("/Yarn") }
        XCTAssertEqual(yarnHits.count, 1)
        XCTAssertEqual(yarnHits.first?.ruleID, ID.yarnCache)
        let brewHits = report.allCandidates.filter { $0.url.path.contains("/Homebrew") }
        XCTAssertEqual(brewHits.map(\.ruleID), [ID.homebrewDownloads])
        let chromeHits = report.allCandidates.filter { $0.url.path.contains("/Google") }
        XCTAssertEqual(chromeHits.map(\.ruleID), [ID.chromeCache])
        XCTAssertGreaterThan(report.result(for: ID.thirdPartyCaches)?.skippedOverlaps ?? 0, 0)
        let paths = report.allCandidates.map { $0.url.standardizedFileURL.path }
        XCTAssertEqual(paths.count, Set(paths).count)
    }

    func testMultiRootRuleScansEveryRootAndNeverProfiles() async throws {
        try fixture.file("Library", "Application Support", "Code", "CachedData", "abc", "blob", bytes: 4000)
        try fixture.file("Library", "Application Support", "Code", "Cache", "Cache_Data", "f_1", bytes: 4000)
        try fixture.file("Library", "Application Support", "Code", "User", "settings.json", bytes: 100)
        try fixture.file("Library", "Application Support", "Code", "User", "globalStorage", "state.vscdb", bytes: 9000)
        let report = try await fixture.scan()
        let result = try XCTUnwrap(report.result(for: ID.vsCodeCaches))
        XCTAssertEqual(result.status, .scanned)
        XCTAssertEqual(Set(result.candidates.map(\.displayName)), ["abc", "Cache_Data"])
        XCTAssertFalse(report.allCandidates.contains { $0.url.path.contains("/User/") })
        XCTAssertTrue(result.candidates.allSatisfy { $0.tier == .review && !$0.isSelectedByDefault })
    }

    func testRunningEditorBlocksItsCaches() async throws {
        try fixture.file("Library", "Application Support", "Code", "CachedData", "abc", "blob", bytes: 4000)
        let report = try await fixture.scan(running: [KnownApp.vsCode.bundleIdentifier])
        XCTAssertTrue(report.result(for: ID.vsCodeCaches)?.candidates.allSatisfy { $0.tier == .blocked } ?? false)
    }

    func testEmptyFoldersAreNotListed() async throws {
        try fixture.dir("Library", "Caches", "Yarn", "v6")
        try fixture.file("Library", "Caches", "Yarn", "v7", "pkg.tgz", bytes: 3000)
        let report = try await fixture.scan()
        XCTAssertEqual(report.result(for: ID.yarnCache)?.candidates.map(\.displayName), ["v7"])
    }

    func testMissingRootsAreReportedAsNotFound() async throws {
        let report = try await fixture.scan()
        XCTAssertEqual(report.result(for: ID.npmCache)?.status, .notFound)
        XCTAssertTrue(report.allCandidates.isEmpty)
        XCTAssertFalse(report.isPartial)
    }

    func testAgeFilterKeepsRecentDiagnosticReports() async throws {
        let old = Date().addingTimeInterval(-30 * 86_400)
        try fixture.file("Library", "Logs", "DiagnosticReports", "Old.ips", bytes: 2000, modified: old)
        try fixture.file("Library", "Logs", "DiagnosticReports", "Recent.ips", bytes: 2000)
        let report = try await fixture.scan()
        let names = report.result(for: ID.diagnosticReports)?.candidates.map(\.displayName)
        XCTAssertEqual(names, ["Old.ips"])
    }

    func testDisabledRulesAreNotScanned() async throws {
        try fixture.file(".npm", "_cacache", "content-v2", "x", bytes: 1000)
        let report = try await fixture.scan(disabled: [ID.npmCache])
        XCTAssertEqual(report.result(for: ID.npmCache)?.status, .disabled)
        XCTAssertTrue(report.result(for: ID.npmCache)?.candidates.isEmpty ?? false)
    }

    func testProtectedLocationsAreDisplayOnly() async throws {
        try fixture.file("Library", "Developer", "CoreSimulator", "Devices", "ABC", "data", bytes: 40_000)
        let report = try await fixture.scan()
        let devices = try XCTUnwrap(report.result(for: ID.simulatorDevices)?.candidates.first)
        XCTAssertEqual(devices.tier, .protected)
        XCTAssertFalse(devices.isSelectable)
        XCTAssertGreaterThanOrEqual(devices.estimatedBytes, 40_000)
    }

    func testCacheNamedAfterRunningAppIsBlocked() async throws {
        try fixture.file("Library", "Caches", "com.example.Running", "x", bytes: 100)
        let report = try await fixture.scan(running: ["com.example.Running"])
        let candidate = report.allCandidates.first { $0.displayName == "com.example.Running" }
        XCTAssertEqual(candidate?.tier, .blocked)
        XCTAssertEqual(candidate?.isSelectable, false)
    }

    func testScanCanBeCancelled() async throws {
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "x", bytes: 1000)
        let scanner = fixture.scanner()
        do {
            _ = try await scanner.scan(ScanConfiguration(rules: CleanupRuleRegistry.builtInRules)) { progress in
                if progress.phase == .discovering { withUnsafeCurrentTask { $0?.cancel() } }
            }
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }
    }

    func testProgressReportsRealPhasesInOrder() async throws {
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "x", bytes: 1000)
        let phases = PhaseRecorder()
        _ = try await fixture.scanner().scan(ScanConfiguration(rules: CleanupRuleRegistry.builtInRules)) { phases.add($0.phase) }
        XCTAssertEqual(phases.distinct, ScanPhase.allCases)
    }

    // 14 (scan side)
    func testUnreadableRootIsReportedNotCrashed() async throws {
        try XCTSkipIf(fixture.isRunningAsRoot, "root ignores permission bits")
        let root = try fixture.dir("Library", "Caches", "Yarn")
        try fixture.file("Library", "Caches", "Yarn", "v6", "x")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let report = try await fixture.scan()
        guard case .permissionDenied = report.result(for: ID.yarnCache)?.status else {
            return XCTFail("expected permissionDenied, got \(String(describing: report.result(for: ID.yarnCache)?.status))")
        }
        XCTAssertTrue(report.isPartial)
    }
}

final class PhaseRecorder: @unchecked Sendable {
    private var phases: [ScanPhase] = []
    private let lock = NSLock()
    func add(_ phase: ScanPhase) { lock.lock(); phases.append(phase); lock.unlock() }
    var distinct: [ScanPhase] {
        lock.lock(); defer { lock.unlock() }
        var out: [ScanPhase] = []
        for phase in phases where out.last != phase { out.append(phase) }
        return out
    }
}
