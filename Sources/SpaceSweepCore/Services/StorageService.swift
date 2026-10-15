import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Live capacity of the volume holding the user's home directory.
public struct VolumeSnapshot: Sendable, Codable, Equatable {
    public let name: String?
    public let totalBytes: Int64
    /// Space available for important usage (includes purgeable space macOS can free on demand).
    public let availableBytes: Int64
    /// Raw free space reported by the file system. Used for before/after cleanup measurements.
    public let freeBytes: Int64?
    public let takenAt: Date

    public init(name: String?, totalBytes: Int64, availableBytes: Int64, freeBytes: Int64?, takenAt: Date = Date()) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.freeBytes = freeBytes
        self.takenAt = takenAt
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

public enum StorageError: Error, Equatable {
    case unavailable
}

public protocol StorageMeasuring: Sendable {
    func snapshot(of url: URL) throws -> VolumeSnapshot
    /// Fresh file-system free-space reading, or nil if it cannot be read.
    func freeBytes(of url: URL) -> Int64?
}

public struct StorageService: StorageMeasuring {
    public init() {}

    public func snapshot(of url: URL) throws -> VolumeSnapshot {
        #if os(macOS)
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [
            .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        guard let total = values.volumeTotalCapacity, total > 0 else { throw StorageError.unavailable }
        let raw = values.volumeAvailableCapacity.map(Int64.init)
        let important = values.volumeAvailableCapacityForImportantUsage
        guard let available = (important.flatMap { $0 > 0 ? $0 : nil }) ?? raw else { throw StorageError.unavailable }
        return VolumeSnapshot(
            name: values.volumeLocalizedName ?? values.volumeName,
            totalBytes: Int64(total),
            availableBytes: available,
            freeBytes: raw
        )
        #else
        guard let stats = Self.statfsValues(url) else { throw StorageError.unavailable }
        return VolumeSnapshot(name: nil, totalBytes: stats.total, availableBytes: stats.free, freeBytes: stats.free)
        #endif
    }

    public func freeBytes(of url: URL) -> Int64? {
        #if os(macOS)
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        if let value = try? fresh.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
            return Int64(value)
        }
        return nil
        #else
        return Self.statfsValues(url)?.free
        #endif
    }

    #if !os(macOS)
    static func statfsValues(_ url: URL) -> (total: Int64, free: Int64)? {
        var info = statvfs()
        let rc = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return statvfs(pointer, &info)
        }
        guard rc == 0 else { return nil }
        let block = Int64(info.f_frsize)
        return (Int64(info.f_blocks) * block, Int64(info.f_bavail) * block)
    }
    #endif
}
