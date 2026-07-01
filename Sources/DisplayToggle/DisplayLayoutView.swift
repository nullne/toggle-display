import SwiftUI

struct DisplayLayoutView: View {
    let manager: DisplayManager

    var body: some View {
        GeometryReader { geometry in
            let layout = computeLayout(
                displays: manager.displays,
                availableSize: geometry.size)

            ZStack {
                ForEach(manager.displays) { display in
                    if let rect = layout[display.id] {
                        DisplayRectView(
                            display: display,
                            canToggle: manager.canToggle(display)
                        ) {
                            manager.toggleDisplay(display)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }

    private func computeLayout(
        displays: [DisplayInfo],
        availableSize: CGSize
    ) -> [CGDirectDisplayID: CGRect] {
        guard !displays.isEmpty else { return [:] }

        // Compute bounding box of all display bounds
        var unionRect = displays[0].bounds
        for display in displays.dropFirst() {
            unionRect = unionRect.union(display.bounds)
        }

        guard unionRect.width > 0, unionRect.height > 0 else { return [:] }

        let padding: CGFloat = 12
        let usableWidth = availableSize.width - padding * 2
        let usableHeight = availableSize.height - padding * 2

        guard usableWidth > 0, usableHeight > 0 else { return [:] }

        let scaleX = usableWidth / unionRect.width
        let scaleY = usableHeight / unionRect.height
        let scale = min(scaleX, scaleY)

        // Center the layout
        let scaledWidth = unionRect.width * scale
        let scaledHeight = unionRect.height * scale
        let offsetX = padding + (usableWidth - scaledWidth) / 2
        let offsetY = padding + (usableHeight - scaledHeight) / 2

        // Add a small visual gap between displays so they don't look merged
        let gap: CGFloat = 2

        var rects: [CGDirectDisplayID: CGRect] = [:]
        for display in displays {
            let x = (display.bounds.origin.x - unionRect.origin.x) * scale + offsetX + gap
            let y = (display.bounds.origin.y - unionRect.origin.y) * scale + offsetY + gap
            let w = max(display.bounds.width * scale - gap * 2, 20)
            let h = max(display.bounds.height * scale - gap * 2, 16)
            rects[display.id] = CGRect(x: x, y: y, width: w, height: h)
        }

        return rects
    }
}
