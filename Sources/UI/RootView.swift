import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var connections = ConnectionStore()
    @StateObject private var keys = KeyStore()
    @StateObject private var forwards = PortForwardStore()
    @State private var activeConnection: SSHConnection?

    var body: some View {
        TabView {
            ConnectionListView(store: connections, keyStore: keys, forwardStore: forwards) { connection in
                activeConnection = connection
            }
            .tabItem { Label("Hosts", systemImage: "server.rack") }

            KeyListView(store: keys, connections: connections)
                .tabItem { Label("Keys", systemImage: "key.fill") }

            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .fullScreenCover(item: $activeConnection) { connection in
            TerminalScreen(
                connection: connection,
                savedConnectionID: connection.savedID,
                forwardStore: forwards
            ) {
                activeConnection = nil
            }
            .environmentObject(ghostty)
        }
    }
}
