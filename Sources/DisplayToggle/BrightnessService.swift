import Foundation
import IOKit
import CoreGraphics
import CPrivateAPIs

final class BrightnessService {
    private var sleepAssertionID: IOPMAssertionID = 0

    private typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    private static let getBrightnessFn: DSGetBrightness? = {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DSGetBrightness.self)
    }()

    private static let setBrightnessFn: DSSetBrightness? = {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DSSetBrightness.self)
    }()

    func turnOff(_ display: DisplayInfo) {
        // Save current brightness
        var currentBrightness: Float = 1.0
        _ = Self.getBrightnessFn?(display.id, &currentBrightness)
        display.previousBrightness = max(currentBrightness, 0.1)

        // Set brightness to 0
        _ = Self.setBrightnessFn?(display.id, 0.0)

        // Prevent display sleep so macOS doesn't sleep the machine
        if sleepAssertionID == 0 {
            IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "DisplayToggle: built-in display off" as CFString,
                &sleepAssertionID)
        }
    }

    func turnOn(_ display: DisplayInfo) {
        let target = display.previousBrightness > 0 ? display.previousBrightness : 1.0
        _ = Self.setBrightnessFn?(display.id, target)

        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }
}
