import Foundation

public enum PathDisplay {
    /// Replaces the home directory with `~` so paths can be shown without exposing the account name.
    public static func shortened(_ url: URL, home: URL) -> String {
        let components = url.standardizedFileURL.pathComponents
        let homeComponents = home.standardizedFileURL.pathComponents
        if components.count >= homeComponents.count, Array(components.prefix(homeComponents.count)) == homeComponents {
            let rest = components.dropFirst(homeComponents.count)
            return (["~"] + rest).joined(separator: "/")
        }
        return url.path
    }

    /// Friendlier names for Xcode DerivedData folders (`MyApp-abcdefghijklmnopqrstuvwxyzab` → `MyApp`).
    public static func friendlyName(for name: String, ruleID: String) -> String {
        if ruleID == CleanupRuleRegistry.ID.xcodeDerivedData,
           let dash = name.lastIndex(of: "-") {
            let suffix = name[name.index(after: dash)...]
            if suffix.count == 28, suffix.allSatisfy({ $0.isLetter && $0.isLowercase }) {
                return String(name[..<dash])
            }
        }
        return name
    }
}
