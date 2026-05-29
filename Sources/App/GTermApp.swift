import SwiftUI

@main
struct GTermApp: App {
    @StateObject private var ghostty = Ghostty.App()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ghostty)
        }
    }
}
