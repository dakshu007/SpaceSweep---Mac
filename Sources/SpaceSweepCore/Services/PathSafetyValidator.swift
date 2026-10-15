import Foundation

public enum ValidationFailure: Error, Equatable, Sendable {
    case notAbsolute
    case containsTraversal
    case notInsideRoot
    case isRootItself
    case protectedLocation
    case versionControlData
    case symbolicLink
    case resolvesOutsideRoot
    case crossesVolume
    case notOwnedByUser
    case missing
    case accessDenied
    case changedSinceScan
    case rootUnavailable
    case rootIsSymbolicLink
    case notADirectoryRoot

    public var userMessage: String {
        switch self {
        case .notAbsolute: return "The path is not absolute."
        case .containsTraversal: return "The path contains “.” or “..” components."
        case .notInsideRoot: return "The item is outside the rule’s approved folder."
        case .isRootItself: return "SpaceSweep never removes a rule’s root folder itself."
        case .protectedLocation: return "This location is protected and is never cleaned."
        case .versionControlData: return "Version-control data is never cleaned."
        case .symbolicLink: return "Symbolic links are never followed or removed."
        case .resolvesOutsideRoot: return "The path passes through a symbolic link."
        case .crossesVolume: return "The item is on a different volume."
        case .notOwnedByUser: return "The item is owned by another user."
        case .missing: return "The item no longer exists."
        case .accessDenied: return "Permission denied."
        case .changedSinceScan: return "The item changed since the scan. Rescan before cleaning."
        case .rootUnavailable: return "The rule’s folder is unavailable."
        case .rootIsSymbolicLink: return "The rule’s folder is (or passes through) a symbolic link."
        case .notADirectoryRoot: return "The rule’s folder is not a directory."
        }
    }
}

/// The gatekeeper between a scan result and a deletion. Every check here is run when a candidate is
/// discovered and again immediately before it is removed.
public struct PathSafetyValidator: Sendable {
    public let environment: PathEnvironment

    public init(environment: PathEnvironment) {
        self.environment = environment
    }

    // MARK: Lexical checks (no file-system access)

    /// Absolute path components, or nil if the path is not absolute.
    static func components(of url: URL) -> [String]? {
        guard url.isFileURL else { return nil }
        let path = url.path
        guard path.hasPrefix("/") else { return nil }
        return path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// True if `url` is `ancestor` or lies inside it, comparing whole path components
    /// (`/a/root-evil` is *not* inside `/a/root`).
    static func isSameOrInside(_ url: URL, _ ancestor: URL) -> Bool {
        guard let child = components(of: url), let parent = components(of: ancestor) else { return false }
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }

    /// Whether a path is protected: inside a protected location, or an ancestor of one.
    public func isProtected(_ url: URL) -> Bool {
        let protectedRoots = environment.systemProtectedRoots + environment.protectedHomeURLs
        for root in protectedRoots {
            if Self.isSameOrInside(url, root) || Self.isSameOrInside(root, url) { return true }
        }
        // The home directory and everything above it.
        if Self.isSameOrInside(environment.homeDirectory, url) { return true }
        return false
    }

    /// Pure, path-only checks that a target is a strict descendant of an approved root.
    public func lexicalFailure(target: URL, root: URL) -> ValidationFailure? {
        guard let targetComponents = Self.components(of: target),
              let rootComponents = Self.components(of: root) else { return .notAbsolute }
        if targetComponents.contains(where: { $0 == ".." || $0 == "." }) { return .containsTraversal }
        if rootComponents.contains(where: { $0 == ".." || $0 == "." }) { return .containsTraversal }
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else { return .notInsideRoot }
        if targetComponents.count == rootComponents.count { return .isRootItself }
        if targetComponents.contains(".git") || targetComponents.contains(".svn") || targetComponents.contains(".hg") {
            return .versionControlData
        }
        // Roots must live strictly inside the home directory.
        guard Self.isSameOrInside(root, environment.homeDirectory),
              rootComponents.count > (Self.components(of: environment.homeDirectory)?.count ?? 0) else {
            return .notInsideRoot
        }
        if isProtected(target) || isProtected(root) { return .protectedLocation }
        return nil
    }

    // MARK: File-system checks

    /// Validates a rule root: an existing real directory inside home, reached without symbolic links,
    /// on the same volume as the home directory.
    public func validateRoot(_ root: URL) -> Result<FileStatus, ValidationFailure> {
        guard let rootComponents = Self.components(of: root),
              let homeComponents = Self.components(of: environment.homeDirectory) else { return .failure(.notAbsolute) }
        if rootComponents.contains(where: { $0 == ".." || $0 == "." }) { return .failure(.containsTraversal) }
        guard rootComponents.count > homeComponents.count,
              Array(rootComponents.prefix(homeComponents.count)) == homeComponents else { return .failure(.notInsideRoot) }

        let rootStatus: FileStatus
        switch FileSystemProbe.lstatus(root) {
        case .success(let status): rootStatus = status
        case .failure(.notFound): return .failure(.rootUnavailable)
        case .failure(.accessDenied): return .failure(.accessDenied)
        case .failure(.other): return .failure(.rootUnavailable)
        }
        if rootStatus.kind == .symbolicLink { return .failure(.rootIsSymbolicLink) }
        guard rootStatus.kind == .directory else { return .failure(.notADirectoryRoot) }

        // No symbolic links anywhere between home and the root.
        guard let realHome = FileSystemProbe.realPath(environment.homeDirectory),
              let realRoot = FileSystemProbe.realPath(root) else { return .failure(.rootUnavailable) }
        let relative = rootComponents.dropFirst(homeComponents.count)
        let expected = ([realHome] + relative).joined(separator: "/")
        guard Self.normalize(realRoot) == Self.normalize(expected) else { return .failure(.rootIsSymbolicLink) }

        if case .success(let homeStatus) = FileSystemProbe.lstatus(environment.homeDirectory),
           homeStatus.device != rootStatus.device {
            return .failure(.crossesVolume)
        }
        return .success(rootStatus)
    }

    /// Full validation of a deletion target. When `expected` is supplied, the object at the path must
    /// be the same one that was scanned.
    public func validate(target: URL, root: URL, expected: CandidateFingerprint? = nil) -> Result<CandidateFingerprint, ValidationFailure> {
        if let failure = lexicalFailure(target: target, root: root) { return .failure(failure) }

        let rootStatus: FileStatus
        switch validateRoot(root) {
        case .success(let status): rootStatus = status
        case .failure(let failure): return .failure(failure)
        }

        let status: FileStatus
        switch FileSystemProbe.lstatus(target) {
        case .success(let value): status = value
        case .failure(.notFound): return .failure(.missing)
        case .failure(.accessDenied): return .failure(.accessDenied)
        case .failure(.other): return .failure(.missing)
        }
        if status.kind == .symbolicLink { return .failure(.symbolicLink) }
        if status.device != rootStatus.device { return .failure(.crossesVolume) }
        if status.ownerID != environment.currentUserID { return .failure(.notOwnedByUser) }

        // The resolved path must be exactly the root's resolved path plus the same child components.
        guard let realRoot = FileSystemProbe.realPath(root),
              let realTarget = FileSystemProbe.realPath(target),
              let targetComponents = Self.components(of: target),
              let rootComponents = Self.components(of: root) else { return .failure(.missing) }
        let expectedPath = ([realRoot] + targetComponents.dropFirst(rootComponents.count)).joined(separator: "/")
        guard Self.normalize(realTarget) == Self.normalize(expectedPath) else { return .failure(.resolvesOutsideRoot) }

        let fingerprint = CandidateFingerprint(status)
        if let expected, expected != fingerprint { return .failure(.changedSinceScan) }
        return .success(fingerprint)
    }

    private static func normalize(_ path: String) -> String {
        "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }
}
