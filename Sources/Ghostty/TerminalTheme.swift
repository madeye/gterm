import Foundation

/// A terminal color theme: background, foreground, and a 16-color ANSI palette.
/// Applied to the ghostty surface by writing a config file consumed via
/// `ghostty_config_load_file`. The "default" theme leaves ghostty's built-in
/// colors untouched (its colors here are only used to draw the Settings preview).
struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    /// 16 hex colors (#rrggbb): ANSI 0–7 then bright 8–15.
    let palette: [String]

    /// The default theme keeps ghostty's compiled-in colors (no override).
    var overridesColors: Bool { id != "default" }

    /// ghostty config-file text for this theme; empty for the default.
    var configText: String {
        guard overridesColors else { return "" }
        var lines = ["background = \(background)", "foreground = \(foreground)"]
        for (i, color) in palette.enumerated() {
            lines.append("palette = \(i)=\(color)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Selection (persisted)

    private static let defaultsKey = "terminalTheme"

    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var selected: TerminalTheme { theme(id: selectedID) }

    static func theme(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }

    // MARK: Built-in themes

    static let all: [TerminalTheme] = [
        TerminalTheme(id: "default", name: "Ghostty Default",
                      background: "#1d1f21", foreground: "#c5c8c6",
                      palette: ["#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
                                "#969896", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#ffffff"]),
        TerminalTheme(id: "dracula", name: "Dracula",
                      background: "#282a36", foreground: "#f8f8f2",
                      palette: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]),
        TerminalTheme(id: "nord", name: "Nord",
                      background: "#2e3440", foreground: "#d8dee9",
                      palette: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]),
        TerminalTheme(id: "solarized-dark", name: "Solarized Dark",
                      background: "#002b36", foreground: "#839496",
                      palette: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                                "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        TerminalTheme(id: "gruvbox-dark", name: "Gruvbox Dark",
                      background: "#282828", foreground: "#ebdbb2",
                      palette: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                                "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]),
        TerminalTheme(id: "catppuccin-mocha", name: "Catppuccin Mocha",
                      background: "#1e1e2e", foreground: "#cdd6f4",
                      palette: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                                "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]),
    ]
}
