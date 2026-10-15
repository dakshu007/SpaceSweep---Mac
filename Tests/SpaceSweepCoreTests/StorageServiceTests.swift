import XCTest
@testable import SpaceSweepCore

final class StorageServiceTests: XCTestCase {
    func testLiveSnapshotHasPlausibleValues() throws {
        let snapshot = try StorageService().snapshot(of: FileManager.default.temporaryDirectory)
        XCTAssertGreaterThan(snapshot.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(snapshot.availableBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.usedFraction, 1)
        XCTAssertNotNil(StorageService().freeBytes(of: FileManager.default.temporaryDirectory))
    }

    // 17
    func testUnavailableMeasurementIsReportedHonestly() {
        XCTAssertThrowsError(try ScriptedStorage([]).snapshot(of: URL(fileURLWithPath: "/")))
        XCTAssertNil(ScriptedStorage([]).freeBytes(of: URL(fileURLWithPath: "/")))
    }

    func testUsedFractionIsClamped() {
        let odd = VolumeSnapshot(name: nil, totalBytes: 100, availableBytes: 500, freeBytes: nil)
        XCTAssertEqual(odd.usedBytes, 0)
        XCTAssertEqual(odd.usedFraction, 0)
        let zero = VolumeSnapshot(name: nil, totalBytes: 0, availableBytes: 0, freeBytes: nil)
        XCTAssertEqual(zero.usedFraction, 0)
    }

    func testSaturatingAddition() {
        XCTAssertEqual(Int64.max.saturatingAdd(10), .max)
        XCTAssertEqual(Int64(5).saturatingAdd(7), 12)
    }
}

final class ActivityLogServiceTests: XCTestCase {
    func testAppendLoadClear() throws {
        let fixture = try Fixture()
        let log = ActivityLogService(fileURL: fixture.base.appendingPathComponent("support/activity.json"))
        XCTAssertEqual(log.load(), [])
        try log.append(ActivityEntry(kind: .scan, status: .success, title: "Scan", detail: "x"))
        try log.append(ActivityEntry(kind: .cleanup, status: .partial, title: "Cleanup", detail: "y"))
        XCTAssertEqual(log.load().map(\.title), ["Cleanup", "Scan"])
        try log.clear()
        XCTAssertEqual(log.load(), [])
    }

    func testPathsAreOnlyRecordedWhenRequested() {
        let item = CleanupReport.ItemOutcome(id: UUID(), ruleID: "r", ruleTitle: "R", displayName: "n",
                                             displayPath: "~/Library/Caches/secret-project", status: .failed,
                                             estimatedBytes: 10, bytesRemoved: 0, message: "Permission denied.")
        let report = CleanupReport(startedAt: Date(), finishedAt: Date(), mode: .reviewed, wasDryRun: false,
                                   wasCancelled: false, items: [item], rules: CleanupExecutor.summaries(from: [item]),
                                   estimatedBytesAttempted: 10, filesystemFreeBytesBefore: nil,
                                   filesystemFreeBytesAfter: nil, messages: [])
        let private_ = ActivityEntry.from(cleanup: report, includePaths: false)
        XCTAssertNil(private_.paths)
        XCTAssertEqual(private_.status, .failed)
        let withPaths = ActivityEntry.from(cleanup: report, includePaths: true)
        XCTAssertEqual(withPaths.paths, ["~/Library/Caches/secret-project"])

        let exportPrivate = ActivityLogService.exportText([withPaths], includePaths: false, appVersion: "0.1.0")
        XCTAssertFalse(exportPrivate.contains("secret-project"))
        let exportPaths = ActivityLogService.exportText([withPaths], includePaths: true, appVersion: "0.1.0")
        XCTAssertTrue(exportPaths.contains("secret-project"))
    }
}
