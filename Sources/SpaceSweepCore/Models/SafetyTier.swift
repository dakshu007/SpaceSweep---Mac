import Foundation

/// Every candidate SpaceSweep finds is placed in exactly one tier.
///
/// - `safe`: generated, rebuildable data matched by an explicit rule. Eligible for one-click cleaning.
/// - `review`: may be rebuildable but can have value to the user. Never selected automatically.
/// - `protected`: display-only. SpaceSweep never offers to delete it.
/// - `blocked`: temporarily unsafe or inaccessible (app running, permission missing, changed since scan…).
public enum SafetyTier: String, Codable, Sendable, CaseIterable, Comparable {
    case safe
    case review
    case protected
    case blocked

    public var title: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Review"
        case .protected: return "Protected"
        case .blocked: return "Blocked"
        }
    }

    public var sectionTitle: String {
        switch self {
        case .safe: return "Safe to clean"
        case .review: return "Review first"
        case .protected: return "Protected"
        case .blocked: return "Unavailable right now"
        }
    }

    /// Only these tiers can ever reach the cleanup executor.
    public var isDeletableTier: Bool { self == .safe || self == .review }

    private var sortOrder: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .blocked: return 2
        case .protected: return 3
        }
    }

    public static func < (lhs: SafetyTier, rhs: SafetyTier) -> Bool { lhs.sortOrder < rhs.sortOrder }
}
