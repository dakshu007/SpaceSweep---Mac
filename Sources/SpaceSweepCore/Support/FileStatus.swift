import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Result of `lstat(2)` — never follows symbolic links.
public struct FileStatus: Sendable, Equatable {
    public enum Kind: String, Sendable, Hashable {
        case directory
        case regularFile
        case symbolicLink
        case other
    }

    public let device: UInt64
    public let inode: UInt64
    public let ownerID: UInt32
    public let kind: Kind
    /// Creation time where the platform reports it (APFS does). Detects an object replaced at the same path.
    public var birthTime: Double? = nil
}

public enum FileSystemError: Error, Equatable, Sendable {
    case notFound
    case accessDenied(errno: Int32)
    case other(errno: Int32)
}

/// Thin, side-effect-free POSIX helpers used by the validator and scanner.
public enum FileSystemProbe {
    public static func lstatus(_ url: URL) -> Result<FileStatus, FileSystemError> {
        var info = stat()
        let rc = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return lstat(pointer, &info)
        }
        guard rc == 0 else {
            let code = errno
            switch code {
            case ENOENT, ENOTDIR: return .failure(.notFound)
            case EACCES, EPERM: return .failure(.accessDenied(errno: code))
            default: return .failure(.other(errno: code))
            }
        }
        let mode = UInt32(info.st_mode) & 0o170000
        let kind: FileStatus.Kind
        switch mode {
        case 0o040000: kind = .directory
        case 0o100000: kind = .regularFile
        case 0o120000: kind = .symbolicLink
        default: kind = .other
        }
        var status = FileStatus(
            device: UInt64(truncatingIfNeeded: info.st_dev),
            inode: UInt64(truncatingIfNeeded: info.st_ino),
            ownerID: UInt32(truncatingIfNeeded: info.st_uid),
            kind: kind
        )
        #if canImport(Darwin)
        status.birthTime = Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1e9
        #endif
        return .success(status)
    }

    /// Fully resolved path via `realpath(3)`. Unlike `URL.resolvingSymlinksInPath()`, this does not
    /// rewrite `/private/var` to `/var`, so results are directly comparable.
    public static func realPath(_ url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { pointer -> String? in
            guard let pointer, let resolved = realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    public static var currentUserID: UInt32 { UInt32(getuid()) }
}
