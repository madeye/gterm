import SwiftUI

struct RootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var connections = ConnectionStore()
    @StateObject private var keys = KeyStore()
    @StateObject private var forwards = PortForwardStore()
    @StateObject private var sessions = SessionManager()
    @State private var activeSession: ActiveSession?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
    @State private var utility: Utility?
    @State private var welcomeAfterUtility = false

    private enum Utility: String, Identifiable {
        case keys, ai, settings
        var id: String { rawValue }
    }

    /// Whether the user has seen the Get Started screen (persisted).
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadWorkspace
            } else {
                phoneTabs
                    .fullScreenCover(item: $activeSession) { session in
                        terminal(session)
                    }
            }
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

    private var hosts: some View {
        ConnectionListView(
            store: connections, keyStore: keys, forwardStore: forwards, sessions: sessions,
            usesNavigationStack: UIDevice.current.userInterfaceIdiom != .pad,
            selectedSessionID: activeSession?.id
        ) { connection in
            let connectionForwards = connection.savedID.map { forwards.forwards(for: $0) } ?? []
            activeSession = sessions.open(connection, ghostty: ghostty, forwards: connectionForwards)
            preferredColumn = .detail
        }
    }

    private var phoneTabs: some View {
        TabView {
            hosts.tabItem { Label("Hosts", systemImage: "server.rack") }
            KeyListView(store: keys, connections: connections)
                .tabItem { Label("Keys", systemImage: "key.fill") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            SettingsView(showWelcome: $showWelcome)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    private var iPadWorkspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            hosts
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { utility = .keys } label: { Label("Keys", systemImage: "key") }
                        Spacer()
                        Button { utility = .ai } label: { Label("AI", systemImage: "sparkles") }
                        Spacer()
                        Button { utility = .settings } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding()
                    .background(.bar)
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let session = activeSession {
                terminal(session)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                ForEach(sessions.sessions) { candidate in
                                    Button {
                                        activeSession = candidate
                                    } label: {
                                        Label(
                                            "\(candidate.connection.username)@\(candidate.connection.host)",
                                            systemImage: candidate.id == session.id ? "checkmark" : "terminal"
                                        )
                                    }
                                }
                            } label: {
                                Label("Sessions", systemImage: "rectangle.stack")
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Select a Host", systemImage: "terminal",
                    description: Text("Open an SSH connection from the sidebar. Your sessions stay connected when you switch hosts.")
                )
                .navigationTitle("Terminal")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $utility, onDismiss: {
            if welcomeAfterUtility {
                welcomeAfterUtility = false
                showWelcome = true
            }
        }) { item in
            Group {
                switch item {
                case .keys: KeyListView(store: keys, connections: connections)
                case .ai: AISettingsView()
                case .settings:
                    SettingsView(showWelcome: Binding(
                        get: { showWelcome },
                        set: { requested in
                            if requested {
                                welcomeAfterUtility = true
                                utility = nil
                            }
                        }
                    ))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Done") { utility = nil }
                    .frame(maxWidth: .infinity).padding().background(.bar)
            }
        }
    }

    private func terminal(_ session: ActiveSession) -> some View {
        TerminalScreen(session: session, forwardStore: forwards, onSwitchSession: { offset in
            let candidates = sessions.sessions
            guard let index = candidates.firstIndex(where: { $0.id == session.id }), !candidates.isEmpty else { return }
            activeSession = candidates[(index + offset + candidates.count) % candidates.count]
        }) {
            sessions.pruneIfDead(session)
            if activeSession?.id == session.id {
                activeSession = nil
                preferredColumn = .sidebar
                columnVisibility = .all
            }
        }
        // A representable must be recreated when switching sessions: its
        // UIView belongs to that session and cannot be replaced in updateUIView.
        .id(session.id)
        .environmentObject(ghostty)
    }

}
