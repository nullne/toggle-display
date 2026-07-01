import Foundation

/// 纯计时/等级判定逻辑，无系统副作用，便于单测。
enum BreakReminderLogic {
    /// 返回自阈值起已跨过的「间隔步数」；未到阈值返回 nil。
    /// 阈值处为 0，之后每过一个间隔 +1，**不封顶** —— 用于判断是否又该再提醒一次，
    /// 即使外观已到最高档，跨入新的一步仍应再弹一次。
    static func reminderStep(
        elapsedSeconds: Int,
        thresholdSeconds: Int,
        intervalSeconds: Int
    ) -> Int? {
        guard elapsedSeconds >= thresholdSeconds else { return nil }
        // 间隔非法时退化为只报第 0 步，避免除零。
        guard intervalSeconds > 0 else { return 0 }
        return (elapsedSeconds - thresholdSeconds) / intervalSeconds
    }

    /// 由步数得到窗口展示等级：封顶 maxLevel（外观最多到最坚决那一档）。
    static func displayLevel(step: Int, maxLevel: Int) -> Int {
        min(max(0, step), maxLevel)
    }

    /// 菜单栏图标的填充比例：已用时长占阈值的比例，钳制到 0...1。
    /// 到达阈值即为满（1），之后一直保持满（超时由图标状态另行表达）。
    static func progressFraction(elapsedSeconds: Int, thresholdSeconds: Int) -> Double {
        guard thresholdSeconds > 0 else { return 1 }
        let f = Double(elapsedSeconds) / Double(thresholdSeconds)
        return min(1, max(0, f))
    }

    /// 解锁时是否应重置计时：仅当锁屏时长严格超过 60 秒。
    static func shouldResetOnUnlock(lockedDurationSeconds: Int) -> Bool {
        lockedDurationSeconds > 60
    }
}
