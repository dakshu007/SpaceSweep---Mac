// Prints on-screen windows owned by SpaceSweep as "x,y,w,h" (used by CI to crop screenshots).
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "SpaceSweep" {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let w = bounds["Width"], let h = bounds["Height"], w > 200, h > 200 else { continue }
    print("\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)),\(Int(w)),\(Int(h))")
}
