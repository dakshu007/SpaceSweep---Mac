import Foundation
import XCTest
@testable import SpaceSweepCore

/// A disposable fixture tree. Every destructive test operates only inside `base`.
final class Fixture {
    let base: URL
    let home: URL
    let outside: URL
    let environment: PathEnvironment

    /// System roots minus the temporary-directory roots (`/tmp`, `/var`, `/private`) the fixture lives in.
    static let testSystemRoots: [URL] = ["/System", "/bin", "/sbin", "/usr", "/Applications", "/Library",
                                         "/Volumes", "/cores", "/etc", "/opt", "/dev"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    init(userID: UInt32 = FileSystemProbe.currentUserID) throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceSweepTests-\(UUID().uuidString)", isDirectory: true)
        home = base.appendingPathComponent("home", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        environment = PathEnvironment(homeDirectory: home, systemProtectedRoots: Self.testSystemRoots, currentUserID: userID)
    }

    deinit {
        // Restore permissions changed by a test, then remove only our own fixture directory.
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.path)
        try? FileManager.default.removeItem(at: base)
    }

    func url(_ components: [String], from start: URL? = nil) -> URL {
        components.reduce(start ?? home) { $0.appendingPathComponent($1) }
    }

    @discardableResult
    func dir(_ components: String..., from start: URL? = nil) throws -> URL {
        let url = url(components, from: start)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ components: String..., bytes: Int = 4096, from start: URL? = nil, modified: Date? = nil) throws -> URL {
        let url = url(components, from: start)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    func symlink(_ components: String..., to destination: URL) throws -> URL {
        let url = url(components)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
        return url
    }

    func root(of ruleID: String) -> URL {
        CleanupRuleRegistry.standard.rule(id: ruleID)!.rootURL(in: environment)
    }

    func exists(_ url: URL) -> Bool {
        if case .success = FileSystemProbe.lstatus(url) { return true }
        return false
    }

    var isRunningAsRoot: Bool { FileSystemProbe.currentUserID == 0 }

    func scanner() -> ScannerService {
        ScannerService(environment: environment, storage: nil)
    }

    func scan(rules: [CleanupRule] = CleanupRuleRegistry.builtInRules, running: Set<String> = [],
              disabled: Set<String> = []) async throws -> ScanReport {
        try await scanner().scan(ScanConfiguration(rules: rules, disabledRuleIDs: disabled, runningBundleIDs: running)) { _ in }
    }

    func executor(running: Set<String> = [], remover: FileRemoving = FoundationFileRemover(),
                  storage: StorageMeasuring? = nil, dryRun: Bool = false) -> CleanupExecutor {
        CleanupExecutor(environment: environment, storage: storage, remover: remover,
                        applications: StaticRunningApplications(running), dryRun: dryRun)
    }
}

/// A storage reading that can be scripted or made unavailable.
final class ScriptedStorage: StorageMeasuring, @unchecked Sendable {
    var readings: [Int64?]
    private let lock = NSLock()
    init(_ readings: [Int64?]) { self.readings = readings }
    func snapshot(of url: URL) throws -> VolumeSnapshot { throw StorageError.unavailable }
    func freeBytes(of url: URL) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return readings.isEmpty ? nil : readings.removeFirst()
    }
}

/// Simulates a removal failure without touching the file system.
struct FailingRemover: FileRemoving {
    let error: Error
    func removeItem(at url: URL) throws { throw error }
}
