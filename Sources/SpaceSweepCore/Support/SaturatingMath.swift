import Foundation

extension Int64 {
    /// Adds without trapping on overflow (clamps to `Int64.max`).
    public func saturatingAdd(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        if overflow { return other > 0 ? .max : .min }
        return result
    }
}
