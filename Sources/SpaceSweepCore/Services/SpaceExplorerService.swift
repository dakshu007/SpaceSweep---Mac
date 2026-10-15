import Foundation

/// One measured folder in the Space Explorer. Read-only: the explorer never deletes anything.
public struct ExplorerEntry: Identifiable, Sendable, Hashable {
    public enum Group: String, Sendable, CaseIterable {
        case library
        case applicationSupport
        case developer
        case hidden

        public var title: String {
            switch self {
            case .library: return "Library"
            case .applicationSupport: return "App data"
            case .developer: return "Developer"
            case .hidden: return "Hidden folders"
            }
        }
    }

    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let displayPath: String
    public let group: Group
    public let bytes: Int64
    public let fileCount: Int
    public let isPartial: Bool
    /// Rules whose roots live inside this folder — SpaceSweep can clean those parts.
    public let coveringRuleIDs: [String]
}

public struct ExplorerProgress: Sendable, Equatable {
    public var currentFolder: String
    public var completedFolders: Int
    public var totalFolders: Int
    public var measuredBytes: Int64

    public init(currentFolder: String, completedFolders: Int, totalFolders: Int, measuredBytes: Int64) {
        self.currentFolder = currentFolder
        self.completedFolders = completedFolders
        self.totalFolders = totalFolders
        self.measuredBytes = measuredBytes
    }

    public var fraction: Double { totalFolders == 0 ? 0 : Double(completedFolders) / Double(totalFolders) }
}

public struct ExplorerReport: Sendable {
    public let finishedAt: Date
    public let entries: [ExplorerEntry]
    /// Folders skipped because they hold private data or are guarded by macOS privacy protections.
    public let skippedPrivateFolders: [String]
    public let unreadableFolders: [String]

    public var totalBytes: Int64 { entries.reduce(0) { $0.saturatingAdd($1.bytes) } }
    public var coveredBytes: Int64 {
        entries.filter { !$0.coveringRuleIDs.isEmpty }.reduce(0) { $0.saturatingAdd($1.bytes) }
    }
}

/// Measures the folders in your Library and hidden home folders that usually make up macOS's
/// "System Data" category, so you can see where the space actually is.
///
/// It never opens Documents, Desktop, Downloads, iCloud, Mail, Messages, Photos, Safari, app
/// containers or credentials, never follows symbolic links, and never deletes anything.
public struct SpaceExplorerService: Sendable {
    public let environment: PathEnvironment
    public let registry: CleanupRuleRegistry
    private let measurer = SizeMeasurer()

    public init(environment: PathEnvironment, registry: CleanupRuleRegistry = .standard) {
        self.environment = environment
        self.registry = registry
    }

    /// ~/Library children never opened (private data or protected by macOS privacy controls).
    public static let skippedLibraryChildren: Set<String> = [
        "Containers", "Group Containers", "Mobile Documents", "CloudStorage", "Mail", "Messages", "Photos",
        "Safari", "Cookies", "Calendars", "Accounts", "Keychains", "IdentityServices", "HomeKit", "Biome",
        "Suggestions", "PersonalizationPortrait", "Sharing", "Daemon Containers", "Autosave Information",
        "Metadata", "Reminders", "Passes", "Shortcuts", "Trial", "DuetExpertCenter", "IntelligencePlatform",
        "Assistant", "Application Scripts", "Preferences",
        // Expanded into their children instead:
        "Application Support", "Developer",
    ]

    /// ~/Library/Application Support children never opened.
    public static let skippedApplicationSupportChildren: Set<String> = [
        "AddressBook", "MobileSync", "com.apple.TCC", "CallHistoryDB", "CallHistoryTransactions", "Knowledge",
        "com.apple.sharedfilelist", "FileProvider", "CloudDocs", "Dock", "AccessibilityBundles",
        "com.apple.spotlight", "Google", "Firefox", "Microsoft Edge", "BraveSoftware", "1Password",
        "Bitwarden", "Dashlane", "KeePassXC",
    ]

    /// Hidden home folders never opened (credentials and keys).
    public static let skippedHiddenFolders: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".kube", ".Trash", ".config", ".password-store", ".netrc", ".azure",
    ]

    public func explore(progress: @Sendable (ExplorerProgress) -> Void) async throws -> ExplorerReport {
        let home = environment.homeDirectory
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var skipped: [String] = []
        var targets: [(URL, ExplorerEntry.Group)] = []

        func children(of url: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                .filter { !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }
                .sorted()
        }

        for name in children(of: library) {
            if Self.skippedLibraryChildren.contains(name) {
                if name != "Application Support" && name != "Developer" { skipped.append("~/Library/\(name)") }
                continue
            }
            targets.append((library.appendingPathComponent(name), .library))
        }
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        for name in children(of: support) {
            if Self.skippedApplicationSupportChildren.contains(name) || name.hasPrefix("com.apple.") {
                skipped.append("~/Library/Application Support/\(name)")
                continue
            }
            targets.append((support.appendingPathComponent(name), .applicationSupport))
        }
        let developer = library.appendingPathComponent("Developer", isDirectory: true)
        for name in children(of: developer) {
            targets.append((developer.appendingPathComponent(name), .developer))
        }
        for name in children(of: home) where name.hasPrefix(".") {
            if Self.skippedHiddenFolders.contains(name) {
                skipped.append("~/\(name)")
                continue
            }
            targets.append((home.appendingPathComponent(name), .hidden))
        }

        let homeDevice: UInt64
        switch FileSystemProbe.lstatus(home) {
        case .success(let status): homeDevice = status.device
        case .failure: return ExplorerReport(finishedAt: Date(), entries: [], skippedPrivateFolders: skipped, unreadableFolders: [])
        }

        let allRuleRoots = registry.rules.flatMap { rule in rule.rootURLs(in: environment).map { (rule.id, $0) } }
        var state = ExplorerProgress(currentFolder: "", completedFolders: 0, totalFolders: targets.count, measuredBytes: 0)
        var entries: [ExplorerEntry] = []
        var unreadable: [String] = []
        var lastEmit = Date.distantPast

        for (url, group) in targets {
            if Task.isCancelled { throw CancellationError() }
            let display = PathDisplay.shortened(url, home: home)
            state.currentFolder = display
            progress(state)
            guard case .success(let status) = FileSystemProbe.lstatus(url), status.kind == .directory,
                  status.device == homeDevice else {
                state.completedFolders += 1
                continue
            }
            let measurement = try measurer.measure(url, device: homeDevice) { _, bytes in
                state.measuredBytes = state.measuredBytes.saturatingAdd(bytes)
                if Date().timeIntervalSince(lastEmit) > 0.1 {
                    lastEmit = Date()
                    progress(state)
                }
                return !Task.isCancelled
            }
            state.completedFolders += 1
            if measurement.fileCount == 0 && measurement.unreadableCount > 0 {
                unreadable.append(display)
                continue
            }
            guard measurement.bytes > 0 else { continue }
            let covering = allRuleRoots
                .filter { PathSafetyValidator.isSameOrInside($0.1, url) || PathSafetyValidator.isSameOrInside(url, $0.1) }
                .map(\.0)
            entries.append(ExplorerEntry(
                url: url, name: url.lastPathComponent, displayPath: display, group: group,
                bytes: measurement.bytes, fileCount: measurement.fileCount, isPartial: measurement.unreadableCount > 0,
                coveringRuleIDs: Array(Set(covering)).sorted()
            ))
        }
        progress(state)
        return ExplorerReport(
            finishedAt: Date(),
            entries: entries.sorted { $0.bytes > $1.bytes },
            skippedPrivateFolders: skipped,
            unreadableFolders: unreadable
        )
    }
}
