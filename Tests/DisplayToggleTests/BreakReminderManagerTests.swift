import XCTest
@testable import DisplayToggle

@MainActor
final class BreakReminderManagerTests: XCTestCase {
    // 回归测试：设置配置属性不得触发 didSet 自赋值导致的无限递归。
    // 修复前，@Observable 把属性变成计算属性，didSet 里的自赋值会递归调用
    // setter → 栈溢出崩溃（点一下 Stepper 就退出）。
    func testSettingConfigDoesNotRecurse() {
        let manager = BreakReminderManager()

        manager.intervalMinutes = 7
        XCTAssertEqual(manager.intervalMinutes, 7)

        manager.thresholdMinutes = 33
        XCTAssertEqual(manager.thresholdMinutes, 33)
    }
}
