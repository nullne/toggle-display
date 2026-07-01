import AppKit

/// 菜单栏图标要表达的休息状态。
enum BreakIconState {
    case disabled   // 功能关闭：普通模板图标
    case filling    // 计时中：蓝色从下往上逐渐填满
    case reached    // 到达阈值：整体橙色，提示该休息了
    case overtime   // 已超时：整体红色，配合脉冲动画更醒目
}

/// 绘制菜单栏状态图标。把 SF Symbol 当作形状遮罩，用 .sourceAtop 着色，
/// 从底部按比例填充，实现「逐渐被颜色填满」的效果。
enum StatusIconRenderer {
    private static let symbolName = "display.2"
    private static let pointSize: CGFloat = 15
    // 目标高度：贴合菜单栏内容区，避免自绘位图超出被裁。
    private static let iconHeight: CGFloat = 16

    /// 功能关闭时的普通模板图标（自动适配深浅色菜单栏）。
    static func templateIcon() -> NSImage? {
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DisplayToggle")
        img?.isTemplate = true
        return img
    }

    /// 根据填充比例与状态绘制彩色图标。
    /// - fraction: 0...1 的填充比例（仅 .filling 用到；.reached/.overtime 视为满）。
    /// - pulseOn: 超时脉冲的高亮相位（true 更亮）。
    /// - appearance: 菜单栏的实际外观，用于把「本体色」解析成黑或白，保证在
    ///   深/浅色菜单栏上都清晰可见（彩色图非模板图，不会自动反色）。
    static func icon(
        fraction: Double,
        state: BreakIconState,
        pulseOn: Bool,
        appearance: NSAppearance
    ) -> NSImage {
        guard state != .disabled else {
            return templateIcon() ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DisplayToggle")
        let symbol = base?.withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: pointSize * 1.4, height: pointSize))
        // 等比缩放到目标高度，宽度按符号原始宽高比，保证完整显示不被裁。
        let scale = iconHeight / max(symbol.size.height, 1)
        let size = NSSize(width: (symbol.size.width * scale).rounded(), height: iconHeight)
        let clamped = max(0, min(1, fraction))

        // 在菜单栏外观下把 labelColor 解析成具体黑/白，作为图标本体色 ——
        // 这样即使还没被填满，图标也和普通菜单栏图标一样清晰。
        var bodyColor = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            bodyColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }

        // 各状态的「已填充」与「未填充」配色。
        let emptyColor: NSColor
        let filledColor: NSColor
        switch state {
        case .disabled:
            emptyColor = .clear; filledColor = .clear   // 不会走到这里
        case .filling:
            emptyColor = bodyColor          // 本体始终清晰
            filledColor = .systemBlue       // 蓝色从底部升起
        case .reached:
            emptyColor = .systemOrange
            filledColor = .systemOrange
        case .overtime:
            let c: NSColor = pulseOn ? .systemRed : NSColor.systemRed.withAlphaComponent(0.4)
            emptyColor = c
            filledColor = c
        }

        let img = NSImage(size: size, flipped: false) { rect in
            // 1) 先画「未填充」底色：整枚符号着 emptyColor。
            symbol.draw(in: rect)
            emptyColor.set()
            rect.fill(using: .sourceAtop)

            // 2) 再画「已填充」部分：仅 .filling 需要按比例从底部覆盖。
            if state == .filling, clamped > 0 {
                let fillRect = NSRect(
                    x: rect.minX, y: rect.minY,
                    width: rect.width, height: rect.height * clamped)
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: fillRect).setClip()
                symbol.draw(in: rect)
                filledColor.set()
                rect.fill(using: .sourceAtop)
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            return true
        }
        img.isTemplate = false   // 彩色图标，不做模板反色
        return img
    }
}
