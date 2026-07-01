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
                         title: "Time for a break",
                         message: "You've been on screen for a while. Get up and move around for a few minutes.")
        case 1:
            return .init(accentColor: .teal,
                         title: "Rest your eyes",
                         message: "A bit more time has passed. Look into the distance and relax.")
        case 2:
            return .init(accentColor: .orange,
                         title: "Really, get up now",
                         message: "Staring at the screen this long isn't good for you. Go grab some water.")
        case 3:
            return .init(accentColor: .red,
                         title: "Stop!",
                         message: "You're well over your limit. Step away from your desk right now.")
        default:
            return .init(accentColor: .red,
                         title: "Enough — stop now!",
                         message: "Your health matters more than work. Lock your screen and rest (over 1 minute resets the timer).")
        }
    }
}

struct BreakReminderView: View {
    let level: Int
    let onDismiss: () -> Void

    private var style: BreakReminderStyle { .forLevel(level) }
    // 字号随等级放大，强化「更坚决」的观感。
    private var titleSize: CGFloat { 20 + CGFloat(level) * 3 }
    // 固定宽度（随等级略增），高度由内容决定 —— 窗口据此自适应大小。
    private var contentWidth: CGFloat { 300 + CGFloat(min(level, 4)) * 24 }

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
                Text("OK, I'll take a break")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(style.accentColor)
        }
        .padding(24)
        .frame(width: contentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style.accentColor, lineWidth: CGFloat(level) + 1))
        )
    }
}
