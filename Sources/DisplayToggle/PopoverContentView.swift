import SwiftUI

struct PopoverContentView: View {
    let manager: DisplayManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Displays")
                .font(.headline)

            DisplayLayoutView(manager: manager)
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)

            Divider()

            CaffeineToggleView(manager: manager)

            Divider()

            BreakReminderSettingsView(manager: manager.breakReminder)

            Divider()

            Button("Quit DisplayToggle") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding()
        .frame(width: 340)
    }
}
