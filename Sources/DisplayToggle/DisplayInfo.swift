import CoreGraphics
import Foundation
import IOKit

@Observable
final class DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    var bounds: CGRect
    let isBuiltIn: Bool
    var isActive: Bool
    var previousBrightness: Float

    var isMain: Bool {
        CGDisplayIsMain(id) != 0
    }

    init(displayID: CGDirectDisplayID) {
        self.id = displayID
        self.bounds = CGDisplayBounds(displayID)
        self.isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        self.isActive = true
        self.previousBrightness = 1.0
        self.name = DisplayInfo.resolveDisplayName(for: displayID)
    }

    static func resolveDisplayName(for displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in Display"
        }

        // Try to get name from IORegistry via CoreDisplay (private framework)
        if let info = coreDisplayCreateInfoDictionary(displayID) as? [String: Any],
           let names = info["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.values.first {
            return name
        }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        if vendor != 0 {
            return "Display \(vendor)-\(model)"
        }
        return "External Display"
    }

    private static func coreDisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> CFDictionary? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }

        typealias Fn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
        guard let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID)?.takeRetainedValue()
    }
}
