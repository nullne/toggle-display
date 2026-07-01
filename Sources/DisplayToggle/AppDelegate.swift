import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let displayManager = DisplayManager()

    // 超时脉冲动画：定时切换高亮相位重绘图标。
    private var pulseTimer: Timer?
    private var pulseOn = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // variableLength：宽度随图标自适应 —— display.2 较宽，squareLength 会把两边裁掉。
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusIconRenderer.templateIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: PopoverContentView(manager: displayManager))
        // 让 popover 随 SwiftUI 内容自适应高度 —— 展开「休息提醒」设置时
        // 才不会把上方内容挤出可视区域。
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        displayManager.startMonitoring()

        // 休息计时的视觉状态变化时刷新菜单栏图标。
        displayManager.breakReminder.onVisualChange = { [weak self] in
            self?.updateBreakIcon()
        }
        updateBreakIcon()
    }

    // MARK: - 菜单栏图标

    private func updateBreakIcon() {
        guard let button = statusItem.button else { return }
        let reminder = displayManager.breakReminder
        let state = reminder.iconState

        switch state {
        case .overtime:
            startPulse()   // 由脉冲定时器负责重绘
        case .disabled, .filling, .reached:
            stopPulse()
            button.image = StatusIconRenderer.icon(
                fraction: reminder.iconFraction, state: state, pulseOn: true,
                appearance: button.effectiveAppearance)
        }
    }

    private func startPulse() {
        guard pulseTimer == nil else { return }
        pulseOn = true
        redrawPulse()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pulseOn.toggle()
                self.redrawPulse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func redrawPulse() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.icon(
            fraction: 1, state: .overtime, pulseOn: pulseOn,
            appearance: button.effectiveAppearance)
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseOn = true
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            displayManager.refreshDisplays()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
