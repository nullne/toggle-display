import AppKit
import SwiftUI

@MainActor
@Observable
final class BreakReminderManager {
    // MARK: - 配置（持久化到 UserDefaults）

    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Keys.enabled)
            if enabled { reset() } else { closeWindow() }
            onVisualChange?()
        }
    }
    // 注意：不要在 didSet 里对属性自赋值做钳制 —— @Observable 会把属性变成
    // 计算属性，自赋值会递归调用 setter 导致栈溢出崩溃。下限由 Stepper 的
    // 取值范围（1...N）与 init 读取时的兜底共同保证。
    var thresholdMinutes: Int {
        didSet {
            defaults.set(thresholdMinutes, forKey: Keys.threshold)
            onVisualChange?()
        }
    }
    var intervalMinutes: Int {
        didSet {
            defaults.set(intervalMinutes, forKey: Keys.interval)
            onVisualChange?()
        }
    }

    private(set) var elapsedMinutes: Int = 0

    /// 每当图标视觉状态可能变化（每次 tick / 重置 / 开关 / 改配置）时回调，
    /// 供 AppDelegate 刷新菜单栏图标。
    var onVisualChange: (@MainActor () -> Void)?

    /// 菜单栏图标的填充比例（0...1）。功能关闭时为 0。
    var iconFraction: Double {
        guard enabled else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        return BreakReminderLogic.progressFraction(
            elapsedSeconds: elapsed, thresholdSeconds: thresholdMinutes * 60)
    }

    /// 菜单栏图标应表达的状态。
    var iconState: BreakIconState {
        guard enabled else { return .disabled }
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        let threshold = thresholdMinutes * 60
        if elapsed < threshold { return .filling }
        // 到达阈值即 reached；再超时至少一个间隔（升级过）则 overtime。
        let step = BreakReminderLogic.reminderStep(
            elapsedSeconds: elapsed,
            thresholdSeconds: threshold,
            intervalSeconds: intervalMinutes * 60) ?? 0
        return step >= 1 ? .overtime : .reached
    }

    // MARK: - 内部状态

    private let maxLevel = 4
    private var sessionStart = Date()
    private var lockedAt: Date?
    /// 已经弹出过的最高「间隔步数」；只有跨入新的一步才再次弹窗。
    /// 用步数而非展示等级，使外观封顶后每过一个间隔仍会反复提醒。
    private var lastSurfacedStep: Int?
    private var tickTimer: Timer?
    private var autoDismissTimer: Timer?
    private var window: NSWindow?

    private let defaults = UserDefaults.standard
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    private enum Keys {
        static let enabled = "BreakReminder.enabled"
        static let threshold = "BreakReminder.thresholdMinutes"
        static let interval = "BreakReminder.intervalMinutes"
    }

    init() {
        enabled = defaults.bool(forKey: Keys.enabled) // 缺省 false
        let t = defaults.integer(forKey: Keys.threshold)
        thresholdMinutes = t > 0 ? t : 45
        let i = defaults.integer(forKey: Keys.interval)
        intervalMinutes = i > 0 ? i : 5
    }

    // MARK: - 生命周期

    func start() {
        sessionStart = Date()
        registerLockObservers()

        // 每 15 秒检查一次已用时长与目标等级。
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func registerLockObservers() {
        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleLock() }
        }
        unlockObserver = center.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlock() }
        }
    }

    // MARK: - 锁屏/解锁

    private func handleLock() {
        lockedAt = Date()
    }

    private func handleUnlock() {
        defer { lockedAt = nil }
        guard let lockedAt else { return }
        let lockedSeconds = Int(Date().timeIntervalSince(lockedAt))
        if BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: lockedSeconds) {
            reset()
        }
    }

    // MARK: - 计时

    private func tick() {
        guard enabled else { return }
        let elapsedSeconds = Int(Date().timeIntervalSince(sessionStart))
        elapsedMinutes = elapsedSeconds / 60
        // 每次 tick 都刷新图标（填充随时间推进），即使还没到弹窗阈值。
        defer { onVisualChange?() }

        guard let step = BreakReminderLogic.reminderStep(
            elapsedSeconds: elapsedSeconds,
            thresholdSeconds: thresholdMinutes * 60,
            intervalSeconds: intervalMinutes * 60
        ) else { return }

        // 跨入新的一步就再提醒一次；外观封顶 maxLevel，
        // 因此到达最高档后每个间隔仍以最坚决的样子反复弹出，直到锁屏 >1 分钟重置。
        if step > (lastSurfacedStep ?? -1) {
            lastSurfacedStep = step
            showWindow(level: BreakReminderLogic.displayLevel(step: step, maxLevel: maxLevel))
        }
    }

    /// 重置计时并清掉已弹窗记录（真正休息后或功能重开时）。
    private func reset() {
        sessionStart = Date()
        elapsedMinutes = 0
        lastSurfacedStep = nil
        closeWindow()
        onVisualChange?()
    }

    // MARK: - 提醒窗口

    private func showWindow(level: Int) {
        closeWindow()

        // 显示在鼠标所在的那块屏幕（用户当前在看的屏），无则退回主屏。
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        // 窗口尺寸由 SwiftUI 内容自适应（固定宽度、高度随内容），避免又空又长。
        let hosting = NSHostingView(rootView: BreakReminderView(level: level) { [weak self] in
            self?.closeWindow()
        })
        let size = hosting.fittingSize

        // 顶部居中，像通知横幅 —— 位置可预期，不再落在大屏正中。
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 24)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating           // 浮于普通窗口，但不用屏蔽层级
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.ignoresMouseEvents = false  // 允许点击按钮
        win.contentView = hosting
        win.orderFrontRegardless()      // 不 makeKey —— 不抢焦点
        window = win

        // 弹窗 30 秒后自动消失；被关闭或消失后，下一个升级间隔才会再弹
        // （未封顶时更大，封顶后以最坚决的样子反复出现）。
        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        autoDismissTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.closeWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoDismissTimer = timer
    }

    private func closeWindow() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        guard let win = window else { return }
        window = nil
        win.orderOut(nil)
        // 沿用黑屏窗口的做法：延到下个 runloop 再释放，避免 CoreAnimation 崩溃。
        let ref = win
        DispatchQueue.main.async { _ = ref }
    }
}
