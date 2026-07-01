import Foundation
import IOKit
import CPrivateAPIs

@Observable
final class CaffeineManager {
    private(set) var isEnabled = false
    private var assertionID: IOPMAssertionID = 0

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private func enable() {
        guard !isEnabled else { return }
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "DisplayToggle: Caffeine Mode" as CFString,
            &assertionID)
        isEnabled = (result == kIOReturnSuccess)
    }

    private func disable() {
        guard isEnabled else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isEnabled = false
    }
}
