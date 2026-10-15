import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Reports which apps are running, by bundle identifier. SpaceSweep never quits apps itself.
public protocol RunningApplicationsProviding: Sendable {
    func runningBundleIdentifiers() async -> Set<String>
}

public struct StaticRunningApplications: RunningApplicationsProviding {
    public let identifiers: Set<String>
    public init(_ identifiers: Set<String> = []) { self.identifiers = identifiers }
    public func runningBundleIdentifiers() async -> Set<String> { identifiers }
}

#if canImport(AppKit)
public struct WorkspaceRunningApplications: RunningApplicationsProviding {
    public init() {}
    public func runningBundleIdentifiers() async -> Set<String> {
        await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    }
}
#endif
