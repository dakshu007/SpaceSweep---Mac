import Darwin
import Foundation
import SpaceSweepCore

/// Read-only facts about space macOS manages itself. Nothing here changes the system:
/// values come from `sysctl`, file metadata and `tmutil listlocalsnapshots` (a listing command).
struct SystemInsights: Sendable, Equatable {
    var purgeableBytes: Int64?
    var swapUsedBytes: Int64?
    var sleepImageBytes: Int64?
    var localSnapshotCount: Int?
    var simulatorRuntimeBytes: Int64?
    var dockerInstalled = false
    var orbStackInstalled = false

    static func gather(volume: VolumeSnapshot?) -> SystemInsights {
        var insights = SystemInsights()
        if let volume, let free = volume.freeBytes, volume.availableBytes > free {
            insights.purgeableBytes = volume.availableBytes - free
        }
        insights.swapUsedBytes = swapUsed()
        insights.sleepImageBytes = allocatedSize(of: URL(fileURLWithPath: "/private/var/vm/sleepimage"))
        insights.localSnapshotCount = localSnapshotCount()
        insights.simulatorRuntimeBytes = simulatorRuntimes()
        insights.dockerInstalled = FileManager.default.fileExists(atPath: "/Applications/Docker.app")
        insights.orbStackInstalled = FileManager.default.fileExists(atPath: "/Applications/OrbStack.app")
        return insights
    }

    private static func swapUsed() -> Int64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Int64(usage.xsu_used)
    }

    private static func allocatedSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { return nil }
        return (values.totalFileAllocatedSize ?? values.fileSize).map(Int64.init)
    }

    /// Counts Time Machine local snapshots using Apple's own listing command (read-only).
    private static func localSnapshotCount() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }

    private static func simulatorRuntimes() -> Int64? {
        let roots = ["/Library/Developer/CoreSimulator/Images", "/Library/Developer/CoreSimulator/Cryptex"]
        var total: Int64 = 0
        var found = false
        for path in roots {
            let url = URL(fileURLWithPath: path)
            guard case .success(let status) = FileSystemProbe.lstatus(url), status.kind == .directory else { continue }
            if let measurement = try? SizeMeasurer().measure(url, device: status.device, tick: { _, _ in true }) {
                total = total.saturatingAdd(measurement.bytes)
                found = true
            }
        }
        return found ? total : nil
    }
}
