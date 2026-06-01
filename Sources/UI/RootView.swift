import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var connections = ConnectionStore()
    @StateObject private var keys = KeyStore()
    @StateObject private var forwards = PortForwardStore()
    @State private var activeConnection: SSHConnection?

    /// Whether the user has seen the Get Started screen (persisted).
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

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

            SettingsView(showWelcome: $showWelcome)
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
        .fullScreenCover(isPresented: $showWelcome) {
            OnboardingView {
                showWelcome = false
                hasSeenWelcome = true
            }
        }
        .onAppear {
            if !hasSeenWelcome { showWelcome = true }
        }
    }
}
