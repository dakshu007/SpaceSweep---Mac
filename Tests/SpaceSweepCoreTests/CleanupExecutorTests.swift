import XCTest
@testable import SpaceSweepCore

final class CleanupExecutorTests: XCTestCase {
    typealias ID = CleanupRuleRegistry.ID
    var fixture: Fixture!

    override func setUpWithError() throws { fixture = try Fixture() }
    override func tearDown() { fixture = nil }

    private func derivedDataPlan(_ names: [String] = ["App-a"]) async throws -> (ScanReport, CleanupPlan) {
        for name in names {
            try fixture.file("Library", "Developer", "Xcode", "DerivedData", name, "Build", "obj.o", bytes: 20_000)
        }
        let report = try await fixture.scan()
        let plan = try CleanupPlanner().makePlan(from: report, selectedIDs: report.defaultSelection)
        return (report, plan)
    }

    func testUnconfirmedPlanRemovesNothing() async throws {
        let (_, plan) = try await derivedDataPlan()
        let report = await fixture.executor().execute(plan)
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.skippedItems, 1)
        XCTAssertTrue(fixture.exists(fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a")))
    }

    func testConfirmedPlanRemovesOnlyChildrenAndKeepsRoot() async throws {
        let keep = try fixture.file("Documents", "keep.txt")
        let (_, plan) = try await derivedDataPlan(["App-a", "App-b"])
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 2)
        XCTAssertEqual(report.failedItems, 0)
        XCTAssertEqual(report.overallStatus, .success)
        XCTAssertGreaterThanOrEqual(report.bytesRemoved, 40_000)
        let root = fixture.root(of: ID.xcodeDerivedData)
        XCTAssertTrue(fixture.exists(root), "root must never be removed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertTrue(fixture.exists(keep))
    }

    func testDryRunRemovesNothing() async throws {
        let (_, plan) = try await derivedDataPlan()
        let report = await fixture.executor(dryRun: true).execute(plan.confirmedByUser())
        XCTAssertTrue(report.wasDryRun)
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertTrue(fixture.exists(fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a")))
    }

    // 8
    func testReviewTargetNeverRunsInOneClickMode() async throws {
        let target = try fixture.dir("Library", "Caches", "Yarn", "v6")
        let fingerprint = CandidateFingerprint(try FileSystemProbe.lstatus(target).get())
        let reviewTarget = PlannedTarget(ruleID: ID.yarnCache, ruleTitle: "Yarn", url: target,
                                         rootURL: fixture.root(of: ID.yarnCache), tier: .review,
                                         estimatedBytes: 1, fingerprint: fingerprint)
        let plan = CleanupPlan(createdAt: Date(), scanFinishedAt: Date(), mode: .oneClickSafe, targets: [reviewTarget],
                               excludedReviewCount: 0, excludedReviewBytes: 0, removesUserFilesPermanently: false,
                               authorization: .oneClickPreference)
        let report = await fixture.executor().execute(plan)
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertTrue(fixture.exists(target))
        XCTAssertNil(plan.authorizedByOneClickPreference())
    }

    // 10
    func testAppLaunchedAfterScanBlocksCleanup() async throws {
        let (_, plan) = try await derivedDataPlan()
        let report = await fixture.executor(running: [KnownApp.xcode.bundleIdentifier]).execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.items.first?.message, "Quit Xcode to clean this.")
        XCTAssertTrue(fixture.exists(fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a")))
    }

    // 11
    func testItemDisappearingBetweenScanAndCleanupIsSkipped() async throws {
        let (_, plan) = try await derivedDataPlan()
        try FileManager.default.removeItem(at: fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a"))
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.skippedItems, 1)
        XCTAssertEqual(report.items.first?.message, ValidationFailure.missing.userMessage)
        XCTAssertNotEqual(report.overallStatus, .success)
    }

    // 12
    func testPathSubstitutedWithSymlinkAfterScanIsRejected() async throws {
        let precious = try fixture.file("precious.txt", from: fixture.outside)
        let (_, plan) = try await derivedDataPlan()
        let target = fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: fixture.outside)
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.items.first?.message, ValidationFailure.symbolicLink.userMessage)
        XCTAssertTrue(fixture.exists(precious))
        XCTAssertTrue(fixture.exists(target))
    }

    func testPathReplacedWithDifferentFolderIsRejected() async throws {
        let (_, plan) = try await derivedDataPlan()
        let target = fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a")
        // Move the scanned folder aside (so its inode stays in use) and put a different one in its place.
        try FileManager.default.moveItem(at: target, to: fixture.outside.appendingPathComponent("App-a-original"))
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "new.txt")
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.items.first?.message, ValidationFailure.changedSinceScan.userMessage)
    }

    // 14
    func testPermissionErrorIsReportedAsFailure() async throws {
        let (_, plan) = try await derivedDataPlan()
        let error = CocoaError(.fileWriteNoPermission, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        let report = await fixture.executor(remover: FailingRemover(error: error)).execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.failedItems, 1)
        XCTAssertEqual(report.overallStatus, .failed)
        XCTAssertEqual(report.bytesRemoved, 0)
        XCTAssertEqual(report.items.first?.message, "Permission denied by file ownership or access controls.")
        XCTAssertEqual(report.rules.first?.status, .failed)
    }

    func testRealPermissionErrorIsHandled() async throws {
        try XCTSkipIf(fixture.isRunningAsRoot, "root ignores permission bits")
        let (_, plan) = try await derivedDataPlan()
        let inner = fixture.root(of: ID.xcodeDerivedData).appendingPathComponent("App-a").appendingPathComponent("Build")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inner.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inner.path) }
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.failedItems, 1)
    }

    // 15
    func testCancelStopsNewTargetsAndReportsAccurately() async throws {
        let (_, plan) = try await derivedDataPlan(["App-a", "App-b", "App-c"])
        let executor = fixture.executor()
        let report = await executor.execute(plan.confirmedByUser()) { progress in
            if progress.deleted == 1 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.deletedItems, 1)
        XCTAssertEqual(report.cancelledItems, 2)
        XCTAssertEqual(report.overallStatus, .cancelled)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.root(of: ID.xcodeDerivedData).path)
        XCTAssertEqual(remaining.count, 2)
    }

    // 16 / 17
    func testEstimatesAreNotReportedAsFreedSpace() async throws {
        let (_, plan) = try await derivedDataPlan()
        // Free space did not move (or moved backwards): no reclaimed figure is reported.
        let flat = await fixture.executor(storage: ScriptedStorage([1_000, 900])).execute(plan.confirmedByUser())
        XCTAssertNil(flat.measuredFreeSpaceChange)
        XCTAssertGreaterThan(flat.estimatedBytesAttempted, 0)
        XCTAssertGreaterThan(flat.bytesRemoved, 0)

        let (_, plan2) = try await derivedDataPlan(["App-z"])
        let unavailable = await fixture.executor(storage: ScriptedStorage([nil, nil])).execute(plan2.confirmedByUser())
        XCTAssertNil(unavailable.filesystemFreeBytesBefore)
        XCTAssertNil(unavailable.measuredFreeSpaceChange)

        let (_, plan3) = try await derivedDataPlan(["App-y"])
        let measured = await fixture.executor(storage: ScriptedStorage([1_000, 51_000])).execute(plan3.confirmedByUser())
        XCTAssertEqual(measured.measuredFreeSpaceChange, 50_000)
    }

    // 19
    func testPathsOutsideTheValidatedPlanAreRejected() async throws {
        let precious = try fixture.file("Documents", "precious.txt")
        let sibling = try fixture.dir("Library", "Developer", "Xcode", "DerivedData-evil")
        let root = try fixture.dir("Library", "Developer", "Xcode", "DerivedData")
        func target(_ url: URL, rule: String = ID.xcodeDerivedData, root rootURL: URL? = nil) throws -> PlannedTarget {
            PlannedTarget(ruleID: rule, ruleTitle: "x", url: url, rootURL: rootURL ?? root, tier: .safe, estimatedBytes: 1,
                          fingerprint: CandidateFingerprint(try FileSystemProbe.lstatus(url).get()))
        }
        let targets = [
            try target(precious),
            try target(sibling),
            try target(root),
            try target(precious, root: fixture.url(["Documents"])),
            try target(precious, rule: "made.up.rule"),
            try target(fixture.home, root: fixture.base),
        ]
        let plan = CleanupPlan(createdAt: Date(), scanFinishedAt: Date(), mode: .reviewed, targets: targets,
                               excludedReviewCount: 0, excludedReviewBytes: 0, removesUserFilesPermanently: false,
                               authorization: .userConfirmed)
        let report = await fixture.executor().execute(plan)
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertEqual(report.skippedItems, targets.count)
        XCTAssertTrue(fixture.exists(precious))
        XCTAssertTrue(fixture.exists(sibling))
        XCTAssertTrue(fixture.exists(root))
    }

    func testProtectedTierCanNeverExecute() async throws {
        let devices = try fixture.dir("Library", "Developer", "CoreSimulator", "Devices", "ABC")
        let protectedTarget = PlannedTarget(ruleID: ID.simulatorDevices, ruleTitle: "x", url: devices,
                                            rootURL: fixture.root(of: ID.simulatorDevices), tier: .protected,
                                            estimatedBytes: 1, fingerprint: CandidateFingerprint(try FileSystemProbe.lstatus(devices).get()))
        let plan = CleanupPlan(createdAt: Date(), scanFinishedAt: Date(), mode: .reviewed, targets: [protectedTarget],
                               excludedReviewCount: 0, excludedReviewBytes: 0, removesUserFilesPermanently: false,
                               authorization: .userConfirmed)
        let report = await fixture.executor().execute(plan)
        XCTAssertEqual(report.deletedItems, 0)
        XCTAssertTrue(fixture.exists(devices))
    }

    func testMultiRootTargetsCleanOnlyInsideTheirOwnRoot() async throws {
        try fixture.file("Library", "Application Support", "Code", "Cache", "Cache_Data", "f_1", bytes: 4000)
        let settings = try fixture.file("Library", "Application Support", "Code", "User", "settings.json", bytes: 100)
        let scan = try await fixture.scan()
        let ids = Set(scan.result(for: ID.vsCodeCaches)?.candidates.map(\.id) ?? [])
        let plan = try CleanupPlanner().makePlan(from: scan, selectedIDs: ids)
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 1)
        XCTAssertTrue(fixture.exists(settings))
        XCTAssertTrue(fixture.exists(fixture.url(["Library", "Application Support", "Code", "Cache"])))

        // A target claiming a root that isn't one of the rule's roots is rejected.
        let user = fixture.url(["Library", "Application Support", "Code", "User"])
        let forged = PlannedTarget(ruleID: ID.vsCodeCaches, ruleTitle: "x", url: settings, rootURL: user, tier: .review,
                                   estimatedBytes: 1, fingerprint: CandidateFingerprint(try FileSystemProbe.lstatus(settings).get()))
        let forgedPlan = CleanupPlan(createdAt: Date(), scanFinishedAt: Date(), mode: .reviewed, targets: [forged],
                                     excludedReviewCount: 0, excludedReviewBytes: 0, removesUserFilesPermanently: false,
                                     authorization: .userConfirmed)
        let forgedReport = await fixture.executor().execute(forgedPlan)
        XCTAssertEqual(forgedReport.deletedItems, 0)
        XCTAssertTrue(fixture.exists(settings))
    }

    func testReviewItemsCleanWhenExplicitlyConfirmed() async throws {
        try fixture.file("Library", "Caches", "Yarn", "v6", "pkg.tgz", bytes: 8000)
        let scan = try await fixture.scan()
        let yarn = try XCTUnwrap(scan.result(for: ID.yarnCache)?.candidates.first)
        let plan = try CleanupPlanner().makePlan(from: scan, selectedIDs: [yarn.id])
        let report = await fixture.executor().execute(plan.confirmedByUser())
        XCTAssertEqual(report.deletedItems, 1)
        XCTAssertTrue(fixture.exists(fixture.root(of: ID.yarnCache)))
        XCTAssertFalse(fixture.exists(yarn.url))
    }
}
