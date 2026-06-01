import SwiftUI

/// The "Settings" tab: re-open the Get Started guide and show app info / links.
struct SettingsView: View {
    /// Set to true to (re-)present the Get Started screen, handled by RootView.
    @Binding var showWelcome: Bool

    @Environment(\.openURL) private var openURL
    /// Easter egg: three taps on the version row open the author's page.
    @State private var versionTaps = 0
    /// Drives the inline preview of the current terminal theme.
    @AppStorage("terminalTheme") private var themeID = "default"

    var body: some View {
        NavigationStack {
            Form {
                Section("Terminal") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        LabeledContent("Color Theme") {
                            HStack(spacing: 8) {
                                Text(TerminalTheme.theme(id: themeID).name)
                                    .foregroundStyle(.secondary)
                                ThemeSwatch(theme: TerminalTheme.theme(id: themeID))
                            }
                        }
                    }
                }

                Section("Help") {
                    Button {
                        showWelcome = true
                    } label: {
                        Label("Get Started Guide", systemImage: "sparkles")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.versionString)
                        .contentShape(Rectangle())
                        .onTapGesture { registerVersionTap() }
                    Link(destination: URL(string: "https://github.com/madeye/gterm")!) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://madeye.github.io/gterm/privacy/")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// Count taps on the version row; every third opens the author's GitHub or
    /// X/Twitter page at random.
    private func registerVersionTap() {
        versionTaps += 1
        guard versionTaps >= 3 else { return }
        versionTaps = 0
        let links = [
            URL(string: "https://github.com/madeye")!,
            URL(string: "https://x.com/m0d8ye")!,
        ]
        openURL(links.randomElement()!)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
