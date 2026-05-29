import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App

    var body: some View {
        let bg = ghostty.config.backgroundColor
        ZStack {
            Color(
                red: Double(bg.r) / 255,
                green: Double(bg.g) / 255,
                blue: Double(bg.b) / 255
            )
            .ignoresSafeArea()

            TerminalView(ghostty: ghostty)
        }
        .preferredColorScheme(.dark)
    }
}
