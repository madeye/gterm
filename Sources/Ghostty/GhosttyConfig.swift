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

            // We have no config file on iOS; just finalize the defaults so the
            // values are usable.
            ghostty_config_finalize(cfg)
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
