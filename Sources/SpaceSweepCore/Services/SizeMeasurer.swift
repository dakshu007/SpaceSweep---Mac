import Foundation

public struct SizeMeasurement: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var fileCount: Int = 0
    public var unreadableCount: Int = 0
    public var skippedLinks: Int = 0
    public var skippedOtherVolumes: Int = 0
}

/// Measures allocated size of a file or folder without following symbolic links or leaving the volume.
public struct SizeMeasurer: Sendable {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    public init() {}

    /// - Parameters:
    ///   - device: volume the measurement must stay on.
    ///   - tick: called periodically with (items examined, bytes measured) deltas. Return false to cancel.
    public func measure(_ url: URL, device: UInt64, tick: (Int, Int64) -> Bool) throws -> SizeMeasurement {
        var result = SizeMeasurement()

        guard case .success(let status) = FileSystemProbe.lstatus(url) else {
            result.unreadableCount = 1
            return result
        }
        switch status.kind {
        case .symbolicLink:
            result.skippedLinks = 1
            return result
        case .regularFile, .other:
            result.bytes = Self.size(of: url)
            result.fileCount = 1
            _ = tick(1, result.bytes)
            return result
        case .directory:
            break
        }

        var unreadable = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Self.keys,
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        )
        guard let enumerator else {
            result.unreadableCount = 1
            return result
        }

        var pendingItems = 0
        var pendingBytes: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: Set(Self.keys))
            if values?.isSymbolicLink == true {
                result.skippedLinks += 1
                // FileManager does not descend into links, but be explicit.
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true {
                if case .success(let childStatus) = FileSystemProbe.lstatus(child) {
                    if childStatus.kind == .symbolicLink {
                        result.skippedLinks += 1
                        enumerator.skipDescendants()
                        continue
                    }
                    if childStatus.device != device {
                        result.skippedOtherVolumes += 1
                        enumerator.skipDescendants()
                    }
                }
                pendingItems += 1
            } else {
                let bytes = Self.size(from: values) ?? Self.size(of: child)
                result.bytes = result.bytes.saturatingAdd(bytes)
                result.fileCount += 1
                pendingItems += 1
                pendingBytes = pendingBytes.saturatingAdd(bytes)
            }
            if pendingItems >= 256 {
                if !tick(pendingItems, pendingBytes) { throw CancellationError() }
                pendingItems = 0
                pendingBytes = 0
            }
        }
        if !tick(pendingItems, pendingBytes) { throw CancellationError() }
        result.unreadableCount += unreadable
        return result
    }

    static func size(from values: URLResourceValues?) -> Int64? {
        guard let values else { return nil }
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        if let logical = values.fileSize { return Int64(logical) }
        return nil
    }

    static func size(of url: URL) -> Int64 {
        size(from: try? url.resourceValues(forKeys: Set(keys))) ?? 0
    }
}
