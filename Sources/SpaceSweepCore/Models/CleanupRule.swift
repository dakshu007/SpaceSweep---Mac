import Foundation

/// An application whose presence matters to a rule (for example, Xcode must be quit
/// before DerivedData is removed). Matched by bundle identifier, never by a guessed process name.
public struct KnownApp: Hashable, Sendable, Codable {
    public let bundleIdentifier: String
    public let displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    public static let xcode = KnownApp(bundleIdentifier: "com.apple.dt.Xcode", displayName: "Xcode")
    public static let simulator = KnownApp(bundleIdentifier: "com.apple.iphonesimulator", displayName: "Simulator")
    public static let chrome = KnownApp(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
    public static let edge = KnownApp(bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge")
    public static let brave = KnownApp(bundleIdentifier: "com.brave.Browser", displayName: "Brave")
    public static let firefox = KnownApp(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox")
}

public enum RuleCategory: String, Sendable, Codable, CaseIterable {
    case xcode
    case simulator
    case packageManager
    case browser
    case appCache
    case logs
    case trash
    case backups

    public var title: String {
        switch self {
        case .xcode: return "Xcode"
        case .simulator: return "Simulators"
        case .packageManager: return "Package managers"
        case .browser: return "Browsers"
        case .appCache: return "App caches"
        case .logs: return "Logs"
        case .trash: return "Trash"
        case .backups: return "Device backups"
        }
    }
}

/// How a rule turns its root into candidates.
public enum RuleScope: Sendable, Hashable {
    /// Each immediate child of the root is an individual candidate.
    /// The root directory itself is never removed.
    case children
    /// The whole root is measured and shown as one display-only item. Never deletable.
    case displayOnlyAggregate
}

/// A single, typed cleanup rule. All cleanup targets come from the central
/// `CleanupRuleRegistry` — never from path strings scattered through the UI.
public struct CleanupRule: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    /// One-line description shown in lists.
    public let summary: String
    /// Why this rule is considered safe / review-only / protected.
    public let explanation: String
    /// What happens after cleaning, and how the data comes back.
    public let consequence: String
    public let tier: SafetyTier
    public let category: RuleCategory
    public let symbolName: String
    /// Root location relative to the user's home directory, as path components.
    public let rootComponents: [String]
    public let scope: RuleScope
    public let requiresClosedApps: [KnownApp]
    public let defaultEnabled: Bool
    public let defaultSelected: Bool
    /// Only children last modified at least this many days ago are offered.
    public let minimumAgeDays: Int?
    public let excludedChildNames: Set<String>
    public let excludedChildPrefixes: [String]
    /// Block a child whose name equals the bundle identifier of a running app.
    public let blocksChildrenNamedAfterRunningApps: Bool
    public let isDeveloperRule: Bool
    /// Location is commonly guarded by macOS privacy protections (TCC).
    public let mayNeedFullDiskAccess: Bool
    /// Items are user files (the Trash) and removal is permanent.
    public let removesUserFilesPermanently: Bool
    /// Supported, manual route for protected locations.
    public let managementHint: String?

    public init(
        id: String,
        title: String,
        summary: String,
        explanation: String,
        consequence: String,
        tier: SafetyTier,
        category: RuleCategory,
        symbolName: String,
        rootComponents: [String],
        scope: RuleScope = .children,
        requiresClosedApps: [KnownApp] = [],
        defaultEnabled: Bool = true,
        defaultSelected: Bool = false,
        minimumAgeDays: Int? = nil,
        excludedChildNames: Set<String> = [],
        excludedChildPrefixes: [String] = [],
        blocksChildrenNamedAfterRunningApps: Bool = false,
        isDeveloperRule: Bool = false,
        mayNeedFullDiskAccess: Bool = false,
        removesUserFilesPermanently: Bool = false,
        managementHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.explanation = explanation
        self.consequence = consequence
        self.tier = tier
        self.category = category
        self.symbolName = symbolName
        self.rootComponents = rootComponents
        self.scope = scope
        self.requiresClosedApps = requiresClosedApps
        self.defaultEnabled = defaultEnabled
        // Only Safe-tier rules may ever be selected by default.
        self.defaultSelected = tier == .safe && scope == .children && defaultSelected
        self.minimumAgeDays = minimumAgeDays
        self.excludedChildNames = excludedChildNames
        self.excludedChildPrefixes = excludedChildPrefixes
        self.blocksChildrenNamedAfterRunningApps = blocksChildrenNamedAfterRunningApps
        self.isDeveloperRule = isDeveloperRule
        self.mayNeedFullDiskAccess = mayNeedFullDiskAccess
        self.removesUserFilesPermanently = removesUserFilesPermanently
        self.managementHint = managementHint
    }

    /// Whether the executor may ever act on candidates from this rule.
    public var isDeletable: Bool { tier.isDeletableTier && scope == .children }

    /// Resolves the root against a home directory, component by component (no string concatenation).
    public func rootURL(in environment: PathEnvironment) -> URL {
        rootComponents.reduce(environment.homeDirectory) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }

    /// `~/Library/Developer/Xcode/DerivedData` style display path.
    public var displayRoot: String {
        (["~"] + rootComponents).joined(separator: "/")
    }

    public func isChildExcluded(named name: String) -> Bool {
        if excludedChildNames.contains(name) { return true }
        return excludedChildPrefixes.contains { name.hasPrefix($0) }
    }
}
