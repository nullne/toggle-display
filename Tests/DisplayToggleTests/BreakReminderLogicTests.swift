import XCTest
@testable import DisplayToggle

final class BreakReminderLogicTests: XCTestCase {
    // 45 分钟阈值、5 分钟间隔、封顶 4
    private let threshold = 45 * 60
    private let interval = 5 * 60

    func testBelowThresholdReturnsNil() {
        XCTAssertNil(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold - 1,
            thresholdSeconds: threshold, intervalSeconds: interval))
    }

    func testAtThresholdReturnsZero() {
        XCTAssertEqual(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold,
            thresholdSeconds: threshold, intervalSeconds: interval), 0)
    }

    func testEachIntervalRaisesStep() {
        XCTAssertEqual(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold + interval,
            thresholdSeconds: threshold, intervalSeconds: interval), 1)
        XCTAssertEqual(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold + 3 * interval,
            thresholdSeconds: threshold, intervalSeconds: interval), 3)
    }

    func testStepIsUncapped() {
        // 步数不封顶：封顶只发生在展示等级层，用于「反复提醒」。
        XCTAssertEqual(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold + 99 * interval,
            thresholdSeconds: threshold, intervalSeconds: interval), 99)
    }

    func testZeroIntervalDoesNotCrash() {
        XCTAssertEqual(BreakReminderLogic.reminderStep(
            elapsedSeconds: threshold + 10,
            thresholdSeconds: threshold, intervalSeconds: 0), 0)
    }

    func testDisplayLevelCapsAtMaxLevel() {
        XCTAssertEqual(BreakReminderLogic.displayLevel(step: 0, maxLevel: 4), 0)
        XCTAssertEqual(BreakReminderLogic.displayLevel(step: 3, maxLevel: 4), 3)
        XCTAssertEqual(BreakReminderLogic.displayLevel(step: 4, maxLevel: 4), 4)
        XCTAssertEqual(BreakReminderLogic.displayLevel(step: 99, maxLevel: 4), 4)
    }

    func testProgressFraction() {
        XCTAssertEqual(BreakReminderLogic.progressFraction(
            elapsedSeconds: 0, thresholdSeconds: threshold), 0, accuracy: 0.0001)
        XCTAssertEqual(BreakReminderLogic.progressFraction(
            elapsedSeconds: threshold / 2, thresholdSeconds: threshold), 0.5, accuracy: 0.0001)
        // 到达或超过阈值都钳制为满。
        XCTAssertEqual(BreakReminderLogic.progressFraction(
            elapsedSeconds: threshold, thresholdSeconds: threshold), 1, accuracy: 0.0001)
        XCTAssertEqual(BreakReminderLogic.progressFraction(
            elapsedSeconds: threshold * 3, thresholdSeconds: threshold), 1, accuracy: 0.0001)
        // 阈值为 0 不崩溃，视为满。
        XCTAssertEqual(BreakReminderLogic.progressFraction(
            elapsedSeconds: 10, thresholdSeconds: 0), 1, accuracy: 0.0001)
    }

    func testShouldResetOnlyAboveSixtySeconds() {
        XCTAssertFalse(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 60))
        XCTAssertFalse(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 30))
        XCTAssertTrue(BreakReminderLogic.shouldResetOnUnlock(lockedDurationSeconds: 61))
    }
}
