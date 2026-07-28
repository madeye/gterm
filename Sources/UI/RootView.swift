import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var connections = ConnectionStore()
    @StateObject private var keys = KeyStore()
    @StateObject private var forwards = PortForwardStore()
    @StateObject private var sessions = SessionManager()
    @State private var activeSession: ActiveSession?

    /// Whether the user has seen the Get Started screen (persisted).
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    var body: some View {
        TabView {
            ConnectionListView(
                store: connections, keyStore: keys, forwardStore: forwards, sessions: sessions
            ) { connection in
                let connectionForwards = connection.savedID.map { forwards.forwards(for: $0) } ?? []
                activeSession = sessions.open(connection, ghostty: ghostty, forwards: connectionForwards)
            }
            .tabItem { Label("Hosts", systemImage: "server.rack") }

            KeyListView(store: keys, connections: connections)
                .tabItem { Label("Keys", systemImage: "key.fill") }

            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }

            SettingsView(showWelcome: $showWelcome)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(item: $activeSession) { session in
            TerminalScreen(session: session, forwardStore: forwards) {
                // Detach only: a live session keeps running in the background
                // so the user can come back to it from the Hosts list.
                sessions.pruneIfDead(session)
                activeSession = nil
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
