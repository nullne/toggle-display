# 屏幕使用时间休息提醒 — 设计文档

## 目标

在 DisplayToggle 菜单栏应用中新增「休息提醒」功能：当用户连续使用屏幕超过配置的时长（默认 45 分钟）时弹窗提醒休息；若一直不休息，则每过一个升级间隔（默认 5 分钟）以更大、更醒目的样子再次提醒。锁屏超过 1 分钟视为真正休息，重置计时。

## 需求

- 可配置「连续使用阈值」（默认 45 分钟），超过后弹出休息提醒。
- 超时后每过「升级间隔」（默认 5 分钟）升级一次提醒，升级只体现为窗口更大、配色更醒目、文案更坚决。
- **重置条件仅为锁屏 > 60 秒**；锁屏 ≤ 60 秒不重置（继续累计）；无操作但未锁屏不算休息。
- 功能默认关闭，需用户在 popover 中手动开启（opt-in）。
- 设置持久化。

## 非目标（YAGNI）

- 不加提示音、不抢焦点、不强制模态、不在多屏同时弹出（仅主屏）。
- 不统计历史使用时长、不做每日报表。
- 不检测系统空闲（idle）作为重置依据。

## 架构与集成

新增 `BreakReminderManager`（`@MainActor @Observable`），与现有 `CaffeineManager` 平级，作为 `DisplayManager` 的属性暴露（沿用 popover 只接收 `DisplayManager` 的现有写法）。

- `DisplayManager` 持有 `let breakReminder = BreakReminderManager()`，在 `startMonitoring()` 中调用 `breakReminder.start()`。
- 配置持久化用 `UserDefaults`，键：
  - `BreakReminder.enabled`（Bool，默认 false）
  - `BreakReminder.thresholdMinutes`（Int，默认 45）
  - `BreakReminder.intervalMinutes`（Int，默认 5）

## 组件

### BreakReminderManager
职责：计时、监听锁屏/解锁、决定何时弹窗及升级等级、管理提醒窗口生命周期。

关键状态：
- `sessionStart: Date` — 当前使用段的起点。
- `lockedAt: Date?` — 记录进入锁屏的时刻。
- `enabled / thresholdMinutes / intervalMinutes` — 从 UserDefaults 读写的配置，供设置 UI 绑定。
- `elapsedMinutes: Int` — 派生的已用分钟数，供设置 UI 显示状态。
- 一个每 15 秒触发的 `Timer`。
- 当前展示的提醒窗口引用与当前已展示的 `level`。

行为：
- `start()`：读取配置；注册 `DistributedNotificationCenter` 观察 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`；启动 15 秒 tick 定时器；`sessionStart = now`。
- 锁屏通知：`lockedAt = now`。
- 解锁通知：若 `lockedAt` 存在且 `now - lockedAt > 60s`，则 `sessionStart = now`（重置）并关闭任何现存提醒窗口；`lockedAt = nil`。
- 每次 tick（仅当 `enabled` 为真）：计算 `elapsed = now - sessionStart`，据下述纯函数得到目标提醒状态并驱动窗口显示/升级。
- `enabled` 从 true 改为 false，或功能被关闭时：关闭现存提醒窗口并把 `sessionStart = now`。

### 纯逻辑（可单测）
抽成不依赖系统 API 的纯函数，放在同文件或独立类型中：

- `reminderStep(elapsedSeconds:thresholdSeconds:intervalSeconds:) -> Int?`
  - `elapsed < threshold` → `nil`（不提醒）。
  - 否则 `floor((elapsed - threshold) / interval)`，**不封顶**（间隔为 0 时退化为 0，避免除零）。
  - 语义为「自阈值起已跨过的间隔步数」，用于判断是否又该再提醒一次 —— 即使外观已封顶，跨入新的一步仍应再弹一次。
- `displayLevel(step:maxLevel:) -> Int` → `min(max(0, step), maxLevel)`，`maxLevel = 4`（外观最多到最坚决那一档）。
- `shouldResetOnUnlock(lockedDurationSeconds:) -> Bool` → `lockedDurationSeconds > 60`。

### BreakReminderWindow / 显示逻辑
复用项目黑屏窗口的做法创建无边框浮动 `NSWindow`：

- 内嵌 SwiftUI `BreakReminderView`，居中于主屏（`NSScreen.main`）。
- 窗口 `level` 设为浮于普通窗口之上（如 `.floating`），**不**用屏蔽层级、**不**抢焦点（`ignoresMouseEvents = false` 以便点按钮，但不 `makeKey` 抢占）。
- 升级映射（由提醒 level 决定）：
  - 尺寸：随 level 递增（如宽度 320 → 560）。
  - 配色：level 0 中性/蓝 → 橙 → 红。
  - 文案：随 level 更坚决（如「该休息一下了」→「你已经连续用眼很久了，起来走走」→「真的该停下来了！」）。
- 展示策略：
  - 记录已弹出过的最高「间隔步数」`lastSurfacedStep`；当计算出的 `step` 跨入新的一步（严格大于 `lastSurfacedStep`，含从「无」到 0）时，以 `displayLevel(step)` 外观显示/刷新窗口。
  - 窗口含「好，休息一下」按钮，点击关闭当前窗口（**不重置计时**）。
  - 窗口在 ~30 秒后自动消失；被关闭或自动消失后，下一个间隔到来时会再次弹出（未封顶时更大，**封顶后以最坚决的样子反复出现**），直到锁屏 >1 分钟重置。

### BreakReminderView（SwiftUI）
根据传入的 level 渲染文案、配色、尺寸，含关闭按钮回调。

### BreakReminderSettingsView（SwiftUI）
放在 `PopoverContentView` 中 `CaffeineToggleView` 下方，新增一个 `Divider()` 分隔：
- 「休息提醒」开关，绑定 `manager.breakReminder.enabled`。
- 阈值分钟数输入（`Stepper` 或 `TextField`，范围合理如 5–180，默认 45）。
- 升级间隔分钟数输入（范围如 1–60，默认 5）。
- 一行状态文字：启用时显示「已连续使用 N 分钟」，未启用时提示已关闭。

## 数据流

`DistributedNotificationCenter`（锁屏/解锁）与 15 秒 `Timer` → `BreakReminderManager` 更新 `sessionStart` / 计算 level → 创建/更新/关闭 `NSWindow(BreakReminderView)`。设置 UI 通过 `@Observable` 双向绑定读写配置，配置变更同步写入 `UserDefaults` 并即时影响计时行为。

## 错误处理与边界

- popover 打开时刷新 `elapsedMinutes` 展示（tick 也会更新）。
- 无主屏（`NSScreen.main == nil`）时跳过弹窗，不崩溃。
- 应用退出或功能关闭时，释放窗口（沿用黑屏窗口的延迟释放规避 CoreAnimation 崩溃的做法）。
- 阈值/间隔配置做下限保护（间隔至少 1 分钟，阈值至少 1 分钟），避免除零或抖动。
- 关闭再开启功能时重置 `sessionStart`，避免用旧起点立刻弹窗。

## 测试

- 单测纯函数：
  - `reminderStep`：低于阈值返回 nil；恰好到阈值返回 0；每加一个间隔加一步；步数不封顶（如第 99 步返回 99）；间隔为 0 不崩溃。
  - `displayLevel`：步数封顶到 maxLevel（如 99 → 4），低步数原样返回。
  - `shouldResetOnUnlock`：60 秒边界（≤60 不重置，>60 重置）。
- 手动验证（系统副作用）：锁屏 <1 分钟不重置、>1 分钟重置；到阈值弹窗；每间隔升级变大；点按钮关闭后下一间隔再弹；开关与配置项即时生效。
