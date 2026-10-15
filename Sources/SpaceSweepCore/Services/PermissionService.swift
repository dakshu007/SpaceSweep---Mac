import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// SpaceSweep is a non-sandboxed personal utility. It reads only rule roots in the user's home folder
/// with normal user permissions. Full Disk Access is optional: it only helps measure locations guarded
/// by macOS privacy protections (the Trash and device backups). It never makes protected files deletable.
public struct PermissionService: Sendable {
    public let environment: PathEnvironment

    public init(environment: PathEnvironment = .live) {
        self.environment = environment
    }

    /// The System Settings pane where the user can grant Full Disk Access.
    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    public static let fullDiskAccessInstructions = "System Settings › Privacy & Security › Full Disk Access, then turn on SpaceSweep."

    /// Detects Full Disk Access by attempting to open (not read) a TCC-protected file.
    public func fullDiskAccessStatus() -> FullDiskAccessStatus {
        #if os(macOS)
        let probe = ["Library", "Application Support", "com.apple.TCC", "TCC.db"]
            .reduce(environment.homeDirectory) { $0.appendingPathComponent($1) }
        let fd = probe.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return open(pointer, O_RDONLY)
        }
        if fd >= 0 {
            close(fd)
            return .granted
        }
        switch errno {
        case EPERM, EACCES: return .notDetected
        default: return .unknown
        }
        #else
        return .unknown
        #endif
    }
}
