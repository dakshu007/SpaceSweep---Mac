import Foundation

/// Where SpaceSweep is allowed to look, and which locations are always off-limits.
/// Tests inject a temporary home directory; the app uses `.live`.
public struct PathEnvironment: Sendable {
    public let homeDirectory: URL
    /// Absolute system roots that are never deletable (and never ancestors of a deletion target).
    public let systemProtectedRoots: [URL]
    public let currentUserID: UInt32

    public init(homeDirectory: URL, systemProtectedRoots: [URL] = PathEnvironment.defaultSystemProtectedRoots,
                currentUserID: UInt32 = FileSystemProbe.currentUserID) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.systemProtectedRoots = systemProtectedRoots.map(\.standardizedFileURL)
        self.currentUserID = currentUserID
    }

    public static var live: PathEnvironment {
        PathEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static let defaultSystemProtectedRoots: [URL] = [
        "/System", "/bin", "/sbin", "/usr", "/Applications", "/Library", "/private", "/var",
        "/Volumes", "/cores", "/etc", "/tmp", "/opt", "/dev", "/Network", "/Users/Shared",
    ].map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// Home-relative locations holding personal data, credentials or app databases. Nothing at,
    /// inside, or above these may ever be deleted.
    public static let protectedHomeLocations: [[String]] = [
        [".ssh"], [".gnupg"], [".aws"], [".kube"], [".docker"], [".config"],
        ["Documents"], ["Desktop"], ["Downloads"], ["Pictures"], ["Movies"], ["Music"], ["Public"],
        ["Applications"],
        ["Library", "Keychains"],
        ["Library", "Mail"],
        ["Library", "Messages"],
        ["Library", "Photos"],
        ["Library", "Safari"],
        ["Library", "Cookies"],
        ["Library", "Calendars"],
        ["Library", "Accounts"],
        ["Library", "Preferences"],
        ["Library", "Containers"],
        ["Library", "Group Containers"],
        ["Library", "Mobile Documents"],
        ["Library", "CloudStorage"],
        ["Library", "IdentityServices"],
        ["Library", "Application Support", "AddressBook"],
        ["Library", "Application Support", "MobileSync"],
        ["Library", "Application Support", "Google", "Chrome"],
        ["Library", "Application Support", "Firefox"],
        ["Library", "Application Support", "Microsoft Edge"],
        ["Library", "Application Support", "BraveSoftware"],
        ["Library", "Developer", "CoreSimulator", "Devices"],
    ]

    public var protectedHomeURLs: [URL] {
        Self.protectedHomeLocations.map { components in
            components.reduce(homeDirectory) { $0.appendingPathComponent($1, isDirectory: true) }
        }
    }
}
