# 屏幕使用时间休息提醒 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DisplayToggle 菜单栏应用中新增可配置的「休息提醒」：连续用屏超过阈值（默认 45 分钟）后弹出提醒窗口，之后每过升级间隔（默认 5 分钟）以更大更醒目的样子再次提醒；锁屏超过 1 分钟重置计时。

**Architecture:** 纯计时/等级判定逻辑抽成无副作用的 `BreakReminderLogic`（可单测）。`BreakReminderManager`（`@MainActor @Observable`）负责计时、监听锁屏/解锁、读写 `UserDefaults` 配置、创建/升级/关闭提醒窗口，作为 `DisplayManager` 的属性暴露，沿用现有 popover 只接收 `DisplayManager` 的写法。SwiftUI 负责提醒窗口内容与 popover 内的设置面板。

**Tech Stack:** Swift 6 / SwiftPM、SwiftUI、AppKit（`NSWindow`）、`DistributedNotificationCenter`（锁屏通知）、`UserDefaults`、XCTest。

## Global Constraints

- 平台：macOS 14+（见 `Package.swift`）。
- 功能默认**关闭**，opt-in。
- 配置项：阈值默认 45 分钟、升级间隔默认 5 分钟；阈值与间隔均下限 1 分钟。
- 升级封顶 `maxLevel = 4`（阈值起第 5 档后不再变大）。
- 重置条件仅为**锁屏 > 60 秒**（60 秒边界为不重置）；不检测系统 idle。
- 升级只改窗口外观（尺寸/配色/文案），不加声音、不抢焦点、仅主屏显示。
- UserDefaults 键：`BreakReminder.enabled`、`BreakReminder.thresholdMinutes`、`BreakReminder.intervalMinutes`。
- 沿用现有代码风格：`@Observable` manager、无 `import` 冗余、注释解释「为什么」。

## File Structure

- Create `Sources/DisplayToggle/BreakReminderLogic.swift` — 纯函数：等级判定、解锁是否重置。无 AppKit/SwiftUI 依赖。
- Create `Sources/DisplayToggle/BreakReminderManager.swift` — 计时、锁屏监听、配置持久化、窗口生命周期。
- Create `Sources/DisplayToggle/BreakReminderView.swift` — 提醒窗口的 SwiftUI 内容 + 按等级的外观样式。
- Create `Sources/DisplayToggle/BreakReminderSettingsView.swift` — popover 内的设置面板。
- Create `Tests/DisplayToggleTests/BreakReminderLogicTests.swift` — 纯逻辑单测。
- Modify `Package.swift` — 新增 test target。
- Modify `Sources/DisplayToggle/DisplayManager.swift` — 持有 `breakReminder`，在 `startMonitoring()` 中 `start()`。
- Modify `Sources/DisplayToggle/PopoverContentView.swift` — 加入设置面板。

---

### Task 1: 纯逻辑 `BreakReminderLogic` + 测试脚手架

**Files:**
- Create: `Sources/DisplayToggle/BreakReminderLogic.swift`
- Create: `Tests/DisplayToggleTests/BreakReminderLogicTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum BreakReminderLogic`
  - `static func reminderLevel(elapsedSeconds: Int, thresholdSeconds: Int, intervalSeconds: Int, maxLevel: Int) -> Int?`
  - `static func shouldResetOnUnlock(lockedDurationSeconds: Int) -> Bool`

- [ ] **Step 1: 新增 test target**

修改 `Package.swift`，在 `targets:` 数组末尾（`executableTarget` 之后）追加：

```swift
        .testTarget(
            name: "DisplayToggleTests",
            dependencies: ["DisplayToggle"],
            path: "Tests/DisplayToggleTests"
        ),
```

- [ ] **Step 2: 写失败测试**

创建 `Tests/DisplayToggleTests/BreakReminderLogicTests.swift`：

```swift
import XCTest
@testable import DisplayToggle

final class BreakReminderLogicTests: XCTestCase {
    // 45 分钟阈值、5 分钟间隔、封顶 4
    private let threshold = 45 * 60
    private let interval = 5 * 60

    func testBelowThresholdReturnsNil() {
        XCTAssertNil(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold - 1,
            thresholdSeconds: threshold, intervalSeconds: interval, maxLevel: 4))
    }

    func testAtThresholdReturnsZero() {
        XCTAssertEqual(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold,
            thresholdSeconds: threshold, intervalSeconds: interval, maxLevel: 4), 0)
    }

    func testEachIntervalRaisesLevel() {
        XCTAssertEqual(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold + interval,
            thresholdSeconds: threshold, intervalSeconds: interval, maxLevel: 4), 1)
        XCTAssertEqual(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold + 3 * interval,
            thresholdSeconds: threshold, intervalSeconds: interval, maxLevel: 4), 3)
    }

    func testLevelCapsAtMaxLevel() {
        XCTAssertEqual(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold + 99 * interval,
            thresholdSeconds: threshold, intervalSeconds: interval, maxLevel: 4), 4)
    }

    func testZeroIntervalDoesNotCrash() {
        XCTAssertEqual(BreakReminderLogic.reminderLevel(
            elapsedSeconds: threshold + 10,
            thresholdSeconds: threshold, intervalSeconds: 0, maxLevel: 4), 0)
    }

    func testShouldResetOnlyAboveSixtySeconds() {
        XCTAssertFalse(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 60))
        XCTAssertFalse(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 30))
        XCTAssertTrue(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 61))
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `swift test 2>&1 | tail -20`
Expected: 编译失败，报 `cannot find 'BreakReminderLogic' in scope`。

- [ ] **Step 4: 写最小实现**

创建 `Sources/DisplayToggle/BreakReminderLogic.swift`：

```swift
import Foundation

/// 纯计时/等级判定逻辑，无系统副作用，便于单测。
enum BreakReminderLogic {
    /// 返回当前应展示的提醒等级；未到阈值返回 nil。
    /// 阈值处为 0，之后每过一个间隔 +1，封顶 maxLevel。
    static func reminderLevel(
        elapsedSeconds: Int,
        thresholdSeconds: Int,
        intervalSeconds: Int,
        maxLevel: Int
    ) -> Int? {
        guard elapsedSeconds >= thresholdSeconds else { return nil }
        // 间隔非法时退化为只报最低等级，避免除零。
        guard intervalSeconds > 0 else { return 0 }
        let steps = (elapsedSeconds - thresholdSeconds) / intervalSeconds
        return min(maxLevel, steps)
    }

    /// 解锁时是否应重置计时：仅当锁屏时长严格超过 60 秒。
    static func shouldResetOnUnlock(lockedDurationSeconds: Int) -> Bool {
        lockedDurationSeconds > 60
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test 2>&1 | tail -20`
Expected: 全部测试 PASS。

- [ ] **Step 6:（无 git，跳过提交）**

项目非 git 仓库，无需 commit。确认 `swift build` 仍成功：`swift build 2>&1 | tail -5`。

---

### Task 2: `BreakReminderManager`（计时 + 锁屏监听 + 配置 + 窗口）

**Files:**
- Create: `Sources/DisplayToggle/BreakReminderManager.swift`

**Interfaces:**
- Consumes: `BreakReminderLogic.reminderLevel(...)`、`BreakReminderLogic.shouldResetOnUnlock(...)`；`BreakReminderView(level:onDismiss:)`（Task 3 提供，本 Task 先用占位内容，Task 3 替换）。
- Produces:
  - `@MainActor @Observable final class BreakReminderManager`
  - `var enabled: Bool`（读写并持久化）
  - `var thresholdMinutes: Int`（读写并持久化，下限 1）
  - `var intervalMinutes: Int`（读写并持久化，下限 1）
  - `private(set) var elapsedMinutes: Int`
  - `func start()`

- [ ] **Step 1: 写实现**

创建 `Sources/DisplayToggle/BreakReminderManager.swift`。注意本 Task 先内嵌一个临时的纯文字窗口内容，Task 3 会替换为 `BreakReminderView`。

```swift
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
        }
    }
    var thresholdMinutes: Int {
        didSet {
            thresholdMinutes = max(1, thresholdMinutes)
            defaults.set(thresholdMinutes, forKey: Keys.threshold)
        }
    }
    var intervalMinutes: Int {
        didSet {
            intervalMinutes = max(1, intervalMinutes)
            defaults.set(intervalMinutes, forKey: Keys.interval)
        }
    }

    private(set) var elapsedMinutes: Int = 0

    // MARK: - 内部状态

    private let maxLevel = 4
    private var sessionStart = Date()
    private var lockedAt: Date?
    /// 已经弹出过的最高等级；只有目标等级更高时才再次弹窗。
    private var lastSurfacedLevel: Int?
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

        guard let target = BreakReminderLogic.reminderLevel(
            elapsedSeconds: elapsedSeconds,
            thresholdSeconds: thresholdMinutes * 60,
            intervalSeconds: intervalMinutes * 60,
            maxLevel: maxLevel
        ) else { return }

        if target > (lastSurfacedLevel ?? -1) {
            lastSurfacedLevel = target
            showWindow(level: target)
        }
    }

    /// 重置计时并清掉已弹窗记录（真正休息后或功能重开时）。
    private func reset() {
        sessionStart = Date()
        elapsedMinutes = 0
        lastSurfacedLevel = nil
        closeWindow()
    }

    // MARK: - 提醒窗口

    private func showWindow(level: Int) {
        closeWindow()
        guard let screen = NSScreen.main else { return } // 无主屏则跳过，不崩溃

        // 尺寸随等级增大 —— 升级越高越醒目。
        let size = CGSize(width: 320 + CGFloat(level) * 60,
                          height: 180 + CGFloat(level) * 24)
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2)

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
        win.contentView = NSHostingView(rootView: BreakReminderView(level: level) { [weak self] in
            self?.closeWindow()
        })
        win.orderFrontRegardless()      // 不 makeKey —— 不抢焦点
        window = win

        // 低等级自动消失；被关闭或消失后，下一个升级间隔才会再弹（更大）。
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
```

- [ ] **Step 2: 编译确认通过**

Run: `swift build 2>&1 | tail -20`
Expected: 编译成功（`BreakReminderView` 需已存在；若尚未做 Task 3，可先临时在本文件内加一个占位 `struct BreakReminderView: View { let level: Int; let onDismiss: () -> Void; var body: some View { Color.blue } }` 以通过编译，Task 3 删除占位并建独立文件）。

> 实施建议：按 Task 顺序做时，先在本文件底部加占位 `BreakReminderView`；进入 Task 3 时删除占位、改用独立文件。若用 subagent 逐 Task，请在本 Task 内保留占位，Task 3 负责替换。

- [ ] **Step 3:（无 git，跳过提交）**

---

### Task 3: `BreakReminderView`（提醒窗口内容 + 等级样式）

**Files:**
- Create: `Sources/DisplayToggle/BreakReminderView.swift`
- Modify: `Sources/DisplayToggle/BreakReminderManager.swift`（删除 Task 2 里的占位 `BreakReminderView`，如有）

**Interfaces:**
- Consumes: 无逻辑依赖。
- Produces:
  - `struct BreakReminderView: View`，初始化 `init(level: Int, onDismiss: @escaping () -> Void)`
  - `struct BreakReminderStyle`，`static func forLevel(_ level: Int) -> BreakReminderStyle`，字段 `accentColor: Color`、`title: String`、`message: String`

- [ ] **Step 1: 写实现**

创建 `Sources/DisplayToggle/BreakReminderView.swift`：

```swift
import SwiftUI

/// 按提醒等级决定配色与文案 —— 等级越高越坚决。
struct BreakReminderStyle {
    let accentColor: Color
    let title: String
    let message: String

    static func forLevel(_ level: Int) -> BreakReminderStyle {
        switch level {
        case 0:
            return .init(accentColor: .blue,
                         title: "该休息一下了",
                         message: "你已经连续用屏一段时间，起来活动几分钟吧。")
        case 1:
            return .init(accentColor: .teal,
                         title: "眼睛需要休息",
                         message: "已经又过了一会儿，看看远处，放松一下。")
        case 2:
            return .init(accentColor: .orange,
                         title: "真的该起来走走了",
                         message: "长时间盯着屏幕对身体不好，去接杯水吧。")
        case 3:
            return .init(accentColor: .red,
                         title: "停下来！",
                         message: "你已经严重超时，请立刻离开座位休息几分钟。")
        default:
            return .init(accentColor: .red,
                         title: "别再撑了！",
                         message: "身体比工作重要，现在就锁屏休息一下（超过 1 分钟即可重新计时）。")
        }
    }
}

struct BreakReminderView: View {
    let level: Int
    let onDismiss: () -> Void

    private var style: BreakReminderStyle { .forLevel(level) }
    // 字号随等级放大，强化「更坚决」的观感。
    private var titleSize: CGFloat { 20 + CGFloat(level) * 3 }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 34 + CGFloat(level) * 4))
                .foregroundStyle(style.accentColor)

            Text(style.title)
                .font(.system(size: titleSize, weight: .bold))
                .multilineTextAlignment(.center)

            Text(style.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Text("好，休息一下")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(style.accentColor)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style.accentColor, lineWidth: CGFloat(level) + 1))
        )
    }
}
```

- [ ] **Step 2: 删除占位（如有）**

若 Task 2 在 `BreakReminderManager.swift` 底部加了占位 `struct BreakReminderView`，现在删除它，改用本独立文件。

- [ ] **Step 3: 编译确认通过**

Run: `swift build 2>&1 | tail -20`
Expected: 编译成功，无重复类型定义报错。

- [ ] **Step 4:（无 git，跳过提交）**

---

### Task 4: 设置面板 + 接入 DisplayManager / Popover

**Files:**
- Create: `Sources/DisplayToggle/BreakReminderSettingsView.swift`
- Modify: `Sources/DisplayToggle/DisplayManager.swift`
- Modify: `Sources/DisplayToggle/PopoverContentView.swift`

**Interfaces:**
- Consumes: `BreakReminderManager`（`enabled`/`thresholdMinutes`/`intervalMinutes`/`elapsedMinutes`/`start()`）。
- Produces:
  - `DisplayManager.breakReminder: BreakReminderManager`
  - `struct BreakReminderSettingsView: View`，`init(manager: BreakReminderManager)`

- [ ] **Step 1: DisplayManager 持有并启动**

修改 `Sources/DisplayToggle/DisplayManager.swift`：

在属性区（`private let caffeineManager = CaffeineManager()` 附近）加入：

```swift
    let breakReminder = BreakReminderManager()
```

在 `startMonitoring()` 方法体末尾加入：

```swift
        breakReminder.start()
```

- [ ] **Step 2: 写设置面板**

创建 `Sources/DisplayToggle/BreakReminderSettingsView.swift`：

```swift
import SwiftUI

struct BreakReminderSettingsView: View {
    @Bindable var manager: BreakReminderManager

    init(manager: BreakReminderManager) {
        self.manager = manager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $manager.enabled) {
                Label("休息提醒", systemImage: "figure.walk.motion")
                    .font(.callout)
            }
            .toggleStyle(.switch)

            if manager.enabled {
                Stepper(value: $manager.thresholdMinutes, in: 1...180) {
                    Text("连续使用 \(manager.thresholdMinutes) 分钟后提醒")
                        .font(.caption)
                }
                Stepper(value: $manager.intervalMinutes, in: 1...60) {
                    Text("每超时 \(manager.intervalMinutes) 分钟升级提醒")
                        .font(.caption)
                }
                Text("已连续使用 \(manager.elapsedMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: 接入 popover**

修改 `Sources/DisplayToggle/PopoverContentView.swift`，在 `CaffeineToggleView(manager: manager)` 之后、`Quit` 前的 `Divider()` 之前插入：

```swift
            Divider()

            BreakReminderSettingsView(manager: manager.breakReminder)
```

修改后该区域应为：`CaffeineToggleView` → `Divider` → `BreakReminderSettingsView` → `Divider` → `Quit` 按钮。

- [ ] **Step 4: 编译确认通过**

Run: `swift build 2>&1 | tail -20`
Expected: 编译成功。

- [ ] **Step 5: 回归测试**

Run: `swift test 2>&1 | tail -10`
Expected: Task 1 的逻辑测试仍全部 PASS。

- [ ] **Step 6: 手动验证（构建 .app）**

Run: `bash Scripts/build.sh 2>&1 | tail -5`
Expected: 生成 `dist/DisplayToggle.app`。手动打开验证：popover 出现「休息提醒」开关；开启后可调阈值/间隔并显示已用分钟；为快速验证可临时把阈值设 1 分钟观察弹窗，以及每间隔升级窗口变大；锁屏 <1 分钟不重置、>1 分钟重置。

- [ ] **Step 7:（无 git，跳过提交）**

---

## Self-Review

- **Spec coverage：** 阈值/间隔可配置（Task 4）、超时弹窗与每间隔升级（Task 2 tick + Task 3 样式）、锁屏 >60s 重置（Task 2 handleUnlock + Logic）、仅锁屏不检测 idle（Task 2 仅注册锁屏通知）、默认关闭 opt-in（Task 2 init + didSet）、持久化（Task 2 UserDefaults）、仅主屏/不抢焦点/无声音（Task 2 showWindow）、封顶 level 4（Task 1/2 maxLevel）、状态显示（Task 4）。均有对应任务。
- **Placeholder scan：** 无 TBD/TODO；代码步骤均含完整代码。Task 2 的占位 `BreakReminderView` 有明确的创建与删除说明。
- **Type consistency：** `BreakReminderView(level:onDismiss:)`、`BreakReminderStyle.forLevel`、`BreakReminderLogic.reminderLevel/shouldResetOnUnlock`、`DisplayManager.breakReminder`、`enabled/thresholdMinutes/intervalMinutes/elapsedMinutes/start()` 在各 Task 间签名一致。
- **风险点：** executable target 的 `@testable import DisplayToggle` 在当前 Swift 6.3 / macOS 14 下受支持；若 `swift test` 报无法导入，退路是把 `BreakReminderLogic.swift` 也加入 test target 的 `sources`（不改结构，仅编译进测试）。
