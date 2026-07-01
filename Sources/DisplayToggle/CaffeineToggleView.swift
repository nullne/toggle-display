import SwiftUI

struct CaffeineToggleView: View {
    let manager: DisplayManager

    var body: some View {
        Toggle(isOn: Binding(
            get: { manager.isCaffeineEnabled },
            set: { manager.isCaffeineEnabled = $0 }
        )) {
            Label("Caffeine Mode", systemImage: "cup.and.saucer.fill")
                .font(.callout)
        }
        .toggleStyle(.switch)
    }
}
