import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var store = ConnectionStore()
    @State private var activeConnection: SSHConnection?

    var body: some View {
        ConnectionListView(store: store) { connection in
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
