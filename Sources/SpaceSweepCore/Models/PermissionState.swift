import Foundation

public enum FullDiskAccessStatus: String, Sendable {
    case granted
    case notDetected
    case unknown

    public var title: String {
        switch self {
        case .granted: return "Full Disk Access granted"
        case .notDetected: return "Full Disk Access not granted"
        case .unknown: return "Full Disk Access status unknown"
        }
    }
}

/// Human-readable access state for the app as a whole.
public enum PermissionState: Sendable, Equatable {
    /// Every enabled rule could be inspected with normal user permissions.
    case noPermissionNeeded
    /// Some enabled locations are guarded by macOS privacy protections.
    case fullDiskAccessWouldHelp(ruleTitles: [String])
    /// Ownership/ACL prevented access to some locations.
    case permissionDenied(ruleTitles: [String])

    public static func from(report: ScanReport) -> PermissionState {
        var tcc: [String] = []
        var denied: [String] = []
        for result in report.ruleResults {
            if case .permissionDenied(let fda) = result.status {
                if fda { tcc.append(result.rule.title) } else { denied.append(result.rule.title) }
            }
        }
        if !tcc.isEmpty { return .fullDiskAccessWouldHelp(ruleTitles: tcc) }
        if !denied.isEmpty { return .permissionDenied(ruleTitles: denied) }
        return .noPermissionNeeded
    }
}
