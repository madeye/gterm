import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var activeConnection: SSHConnection?

    var body: some View {
        ConnectionFormView { connection in
            activeConnection = connection
        }
        .fullScreenCover(item: $activeConnection) { connection in
            TerminalScreen(connection: connection) {
                activeConnection = nil
            }
            .environmentObject(ghostty)
        }
    }
}
