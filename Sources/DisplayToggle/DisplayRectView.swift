import SwiftUI

struct DisplayRectView: View {
    let display: DisplayInfo
    let canToggle: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(display.isActive
                          ? Color.blue.opacity(0.25)
                          : Color.gray.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                display.isActive ? Color.blue : Color.gray,
                                lineWidth: 2))

                VStack(spacing: 2) {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.title3)
                        .foregroundColor(display.isActive ? .blue : .gray)

                    Text(display.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    let w = Int(display.bounds.width)
                    let h = Int(display.bounds.height)
                    Text("\(w)×\(h)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(4)
            }
        }
        .buttonStyle(.plain)
        .opacity(canToggle || !display.isActive ? 1.0 : 0.5)
        .help(canToggle
              ? "Click to toggle \(display.name)"
              : "Cannot turn off the last active display")
    }
}
