import SwiftUI

extension Color {
    /// Build a Color from a `#rrggbb` (or `rrggbb`) hex string.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self = Color(
            red: Double((v >> 16) & 0xff) / 255.0,
            green: Double((v >> 8) & 0xff) / 255.0,
            blue: Double(v & 0xff) / 255.0
        )
    }
}

/// A live mini-terminal preview of a theme: a sample prompt + ANSI swatches on
/// the theme's background.
struct ThemePreview: View {
    let theme: TerminalTheme

    var body: some View {
        let fg = Color(hex: theme.foreground)
        VStack(alignment: .leading, spacing: 6) {
            (Text("dev").foregroundStyle(Color(hex: theme.palette[2]))
                + Text("@host").foregroundStyle(fg)
                + Text(":~$ ").foregroundStyle(Color(hex: theme.palette[4]))
                + Text("ls").foregroundStyle(fg))
                .font(.system(size: 12, design: .monospaced))
            HStack(spacing: 5) {
                ForEach(1..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: theme.palette[i]))
                        .frame(width: 16, height: 9)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A tiny inline swatch (background + a few ANSI dots) for the Settings row.
struct ThemeSwatch: View {
    let theme: TerminalTheme
    var body: some View {
        HStack(spacing: 3) {
            ForEach([1, 2, 4, 5], id: \.self) { i in
                Circle().fill(Color(hex: theme.palette[i])).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Lists the terminal color themes with a preview each; selecting one applies it
/// to newly opened sessions.
struct ThemePickerView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @AppStorage("terminalTheme") private var selectedID = "default"

    var body: some View {
        List {
            Section {
                ForEach(TerminalTheme.all) { theme in
                    Button {
                        selectedID = theme.id
                        ghostty.reloadConfig()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(theme.name).foregroundStyle(.primary)
                                Spacer()
                                if theme.id == selectedID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            ThemePreview(theme: theme)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Applies to terminal sessions you open after changing it.")
            }
        }
        .navigationTitle("Terminal Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
