import XCTest
@testable import SpaceSweepCore

final class SpaceExplorerServiceTests: XCTestCase {
    func testMeasuresLibraryAppDataAndHiddenFoldersButSkipsPrivateOnes() async throws {
        let fixture = try Fixture()
        try fixture.file("Library", "Caches", "com.example.App", "blob", bytes: 50_000)
        try fixture.file("Library", "Application Support", "Code", "CachedData", "x", bytes: 30_000)
        try fixture.file("Library", "Application Support", "SomeApp", "db.sqlite", bytes: 20_000)
        try fixture.file("Library", "Developer", "CoreSimulator", "Devices", "A", "data", bytes: 40_000)
        try fixture.file(".ollama", "models", "blob", bytes: 60_000)
        try fixture.file(".npm", "_cacache", "x", bytes: 10_000)
        // Private: must never be opened or listed.
        try fixture.file("Library", "Containers", "com.example.Sandboxed", "Data", "secret", bytes: 90_000)
        try fixture.file("Library", "Mail", "V10", "mail.emlx", bytes: 90_000)
        try fixture.file(".ssh", "id_ed25519", bytes: 500)
        try fixture.file("Documents", "thesis.pages", bytes: 90_000)

        let report = try await SpaceExplorerService(environment: fixture.environment).explore { _ in }
        let paths = report.entries.map(\.displayPath)
        XCTAssertEqual(paths.first, "~/.ollama")
        XCTAssertTrue(paths.contains("~/Library/Caches"))
        XCTAssertTrue(paths.contains("~/Library/Application Support/Code"))
        XCTAssertTrue(paths.contains("~/Library/Application Support/SomeApp"))
        XCTAssertTrue(paths.contains("~/Library/Developer/CoreSimulator"))
        XCTAssertTrue(paths.contains("~/.npm"))
        for privatePath in ["~/Library/Containers", "~/Library/Mail", "~/.ssh", "~/Documents"] {
            XCTAssertFalse(paths.contains { $0.hasPrefix(privatePath) }, privatePath)
        }
        XCTAssertTrue(report.skippedPrivateFolders.contains("~/Library/Containers"))
        XCTAssertTrue(report.skippedPrivateFolders.contains("~/.ssh"))

        let code = try XCTUnwrap(report.entries.first { $0.name == "Code" })
        XCTAssertEqual(code.coveringRuleIDs, [CleanupRuleRegistry.ID.vsCodeCaches])
        let someApp = try XCTUnwrap(report.entries.first { $0.name == "SomeApp" })
        XCTAssertTrue(someApp.coveringRuleIDs.isEmpty)
        XCTAssertTrue(report.entries.first { $0.name == ".npm" }?.coveringRuleIDs.contains(CleanupRuleRegistry.ID.npmCache) ?? false)

        // Read-only: everything is still there.
        XCTAssertTrue(fixture.exists(fixture.url([".ollama", "models", "blob"])))
    }

    func testDoesNotFollowSymlinks() async throws {
        let fixture = try Fixture()
        try fixture.file("huge.bin", bytes: 1_000_000, from: fixture.outside)
        try fixture.symlink(".linked", to: fixture.outside)
        try fixture.file(".real", "x", bytes: 1000)
        let report = try await SpaceExplorerService(environment: fixture.environment).explore { _ in }
        XCTAssertFalse(report.entries.contains { $0.name == ".linked" })
        XCTAssertLessThan(report.totalBytes, 1_000_000)
    }

    func testCanBeCancelled() async throws {
        let fixture = try Fixture()
        try fixture.file(".a", "x", bytes: 1000)
        try fixture.file(".b", "x", bytes: 1000)
        do {
            _ = try await SpaceExplorerService(environment: fixture.environment).explore { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }
}
