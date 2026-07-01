import CoreGraphics
import AppKit
import Foundation

@MainActor
@Observable
final class DisplayManager {
    var displays: [DisplayInfo] = []

    private let ddcService = DDCService()
    private let brightnessService = BrightnessService()
    private let caffeineManager = CaffeineManager()
    let breakReminder = BreakReminderManager()
    private var debounceWorkItem: DispatchWorkItem?
    private var blackoutWindows: [CGDirectDisplayID: NSWindow] = [:]

    var isCaffeineEnabled: Bool {
        get { caffeineManager.isEnabled }
        set { caffeineManager.setEnabled(newValue) }
    }

    // MARK: - Display Discovery

    func refreshDisplays() {
        ddcService.invalidateCache()

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        CGGetOnlineDisplayList(UInt32(displayIDs.count), &displayIDs, &displayCount)

        // Filter out mirrored displays — they share the same bounds
        // and would render on top of each other
        let currentIDs = displayIDs.prefix(Int(displayCount)).filter { id in
            CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
        }
        let existingIDs = Set(displays.map { $0.id })
        let currentIDSet = Set(currentIDs)

        // Add new displays
        for id in currentIDs where !existingIDs.contains(id) {
            displays.append(DisplayInfo(displayID: id))
        }

        // Update bounds for existing displays (they may have changed after wake)
        for display in displays {
            display.bounds = CGDisplayBounds(display.id)
        }

        // Remove disconnected displays (also clean up blackout windows)
        for display in displays where !currentIDSet.contains(display.id) {
            removeBlackout(for: display.id)
        }
        displays.removeAll { !currentIDSet.contains($0.id) }
    }

    // MARK: - Hot-plug Monitoring

    func startMonitoring() {
        refreshDisplays()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in
            guard let userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { [weak manager] in
                manager?.debouncedRefresh()
            }
        }, selfPtr)

        breakReminder.start()
    }

    private func debouncedRefresh() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshDisplays()
        }
        debounceWorkItem = work
        // Wait 1.5s for all displays to finish waking and stabilize their arrangement.
        // Displays come online at different times, and macOS reports temporary/overlapping
        // coordinates during the transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Toggle Logic

    func canToggle(_ display: DisplayInfo) -> Bool {
        if display.isActive {
            let activeCount = displays.filter(\.isActive).count
            return activeCount > 1
        }
        return true
    }

    func toggleDisplay(_ display: DisplayInfo) {
        guard canToggle(display) else {
            NSSound.beep()
            return
        }

        if display.isActive {
            turnOff(display)
        } else {
            turnOn(display)
        }
    }

    private func turnOff(_ display: DisplayInfo) {
        if display.isBuiltIn {
            brightnessService.turnOff(display)
        } else if ddcService.isAvailable(for: display.id) {
            ddcService.setPowerState(displayID: display.id, on: false)
        } else {
            // Fallback: cover the display with a black window instead of CGDisplayCapture.
            // CGDisplayCapture exclusively captures the display, which breaks hot corners,
            // input methods, desktop switching, and other system features.
            showBlackout(for: display.id)
        }
        display.isActive = false
    }

    private func turnOn(_ display: DisplayInfo) {
        if display.isBuiltIn {
            brightnessService.turnOn(display)
        } else if ddcService.isAvailable(for: display.id) {
            ddcService.setPowerState(displayID: display.id, on: true)
        } else {
            removeBlackout(for: display.id)
        }
        display.isActive = true
    }

    // MARK: - Blackout Window Fallback

    private func showBlackout(for displayID: CGDirectDisplayID) {
        guard blackoutWindows[displayID] == nil else { return }

        // CGDisplayBounds uses top-left origin (CG coordinates).
        // NSWindow uses bottom-left origin (AppKit coordinates).
        // Convert via the main screen's height.
        let cgBounds = CGDisplayBounds(displayID)
        guard let mainScreen = NSScreen.screens.first else { return }
        let mainHeight = mainScreen.frame.height

        let frame = NSRect(
            x: cgBounds.origin.x,
            y: mainHeight - cgBounds.origin.y - cgBounds.height,
            width: cgBounds.width,
            height: cgBounds.height)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.animationBehavior = .none
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true  // Let events pass through to the system
        window.orderFrontRegardless()

        blackoutWindows[displayID] = window
    }

    private func removeBlackout(for displayID: CGDirectDisplayID) {
        guard let window = blackoutWindows.removeValue(forKey: displayID) else { return }
        window.orderOut(nil)
        // Prevent CoreAnimation crash: defer final release until the next run loop cycle
        // so CA can finish any pending transactions referencing the window.
        let ref = window
        DispatchQueue.main.async { _ = ref }
    }
}
