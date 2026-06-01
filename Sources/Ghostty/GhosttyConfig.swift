import Foundation
import GhosttyKit

extension Ghostty {
    /// Thin wrapper around `ghostty_config_t`. For now we use ghostty's
    /// compiled-in defaults plus a couple of mobile-friendly tweaks; a full
    /// settings UI comes later.
    final class Config {
        let c: ghostty_config_t

        init() {
            guard let cfg = ghostty_config_new() else {
                fatalError("ghostty_config_new failed")
            }
            self.c = cfg

            // Apply the user-selected terminal color theme (if not the default)
            // by writing its colors to a config file and loading it.
            Self.applyTheme(to: cfg)

            ghostty_config_finalize(cfg)
        }

        /// Write the selected theme's colors to a temp config file and load it.
        /// No-op for the default theme (keeps ghostty's compiled-in colors).
        private static func applyTheme(to cfg: ghostty_config_t) {
            let text = TerminalTheme.selected.configText
            guard !text.isEmpty else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gterm-theme.conf")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                url.path.withCString { ghostty_config_load_file(cfg, $0) }
            } catch {
                Ghostty.logger.error("failed to write theme config: \(String(describing: error), privacy: .public)")
            }
        }

        deinit {
            ghostty_config_free(c)
        }

        /// The default background color (RGB) from the config, used so the
        /// SwiftUI chrome can match the terminal background.
        var backgroundColor: (r: UInt8, g: UInt8, b: UInt8) {
            var color = ghostty_config_color_s()
            let key = "background"
            let ok = key.withCString { ptr in
                ghostty_config_get(c, &color, ptr, UInt(key.utf8.count))
            }
            guard ok else { return (0x1d, 0x1f, 0x21) }
            return (color.r, color.g, color.b)
        }
    }
}
