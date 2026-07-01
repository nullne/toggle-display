import SwiftUI

struct BreakReminderSettingsView: View {
    @Bindable var manager: BreakReminderManager
    // 配置默认收起，点箭头展开。
    @State private var showConfig = false

    init(manager: BreakReminderManager) {
        self.manager = manager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $manager.enabled) {
                Label("Break Reminder", systemImage: "figure.walk.motion")
                    .font(.callout)
            }
            .toggleStyle(.switch)

            if manager.enabled {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showConfig.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(showConfig ? 90 : 0))
                        Text("Settings")
                            .font(.caption)
                        Spacer()
                        // 收起时用一行摘要展示当前配置与已用时长。
                        Text("\(manager.thresholdMinutes)m · +\(manager.intervalMinutes)m · used \(manager.elapsedMinutes)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showConfig {
                    Stepper(value: $manager.thresholdMinutes, in: 1...180) {
                        Text("Remind after \(manager.thresholdMinutes) min of use")
                            .font(.caption)
                    }
                    Stepper(value: $manager.intervalMinutes, in: 1...60) {
                        Text("Escalate every \(manager.intervalMinutes) min overtime")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
