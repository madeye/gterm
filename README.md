# gterm

An iOS terminal app that renders with [ghostty](../ghostty)'s `libghostty`
engine (GPU/Metal, full xterm/VT emulation) and connects over **SSH**.

> 📲 **Try the beta:** [Join on TestFlight](https://testflight.apple.com/join/qDNYS7fd) (iOS 17+, requires Apple's TestFlight app).
> Or sideload via [AltStore / SideStore](https://madeye.github.io/gterm/altstore/) — source URL `https://madeye.github.io/gterm/altstore.json`.

iOS can't `fork`/`exec` a local shell, so gterm drives the terminal from an SSH
connection via a custom **passthru IO backend** added to libghostty. See
[PLAN.md](PLAN.md) for the full architecture.

## Status

- ✅ libghostty `passthru` IO backend ([madeye/ghostty](https://github.com/madeye/ghostty))
- ✅ iOS app; ghostty terminal surface renders on device/simulator
- ✅ Lean Swift layer over libghostty (app, surface view, input)
- ✅ SSH transport (swift-nio-ssh): password auth, PTY shell, window-change
- ✅ Custom on-screen keyboard (esc/ctrl/alt/tab/arrows/symbols, sticky mods)
- ✅ Saved connections (Keychain passwords) + trust-on-first-use host keys
- ✅ Public-key auth: a Keys tab to import Ed25519/ECDSA keys (stored in the
  Keychain, device-only); each host can select one or more keys to try
- ⏳ Encrypted (passphrase) keys, RSA, richer settings (font/theme)

## Building

Requirements: macOS, Xcode 26+, and the patched Homebrew zig:

```sh
brew install zig@0.15        # keg-only; the build script uses it by full path
brew install xcodegen
```

0. Get the terminal engine. gterm uses a fork of ghostty that adds a
   `passthru` IO backend (so the terminal can be driven by SSH instead of a
   local shell). It's bundled as a git submodule — check it out with:

   ```sh
   git submodule update --init ghostty
   ```

   (If you cloned without `--recurse-submodules`, the command above fetches it.
   To use a separate checkout instead, pass `GHOSTTY_DIR=/path/to/ghostty` to
   the build script below.)

1. Build the terminal engine (cross-compiles `GhosttyKit.xcframework` with
   macOS + iOS + iOS-simulator slices, and applies the required iOS patch to
   libghostty's event loop):

   ```sh
   ./scripts/build-ghostty-xcframework.sh
   ```

2. Generate the Xcode project and build:

   ```sh
   xcodegen generate
   xcodebuild -project gterm.xcodeproj -scheme gterm \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO build
   ```

   Or open `gterm.xcodeproj` in Xcode and run.

`gterm.xcodeproj`, `Info.plist`, and `GhosttyKit.xcframework` are generated and
git-ignored.

## Releasing for AltStore

`scripts/build-altstore-ipa.sh` produces an **unsigned** `.ipa` suitable for
sideloading via AltStore / SideStore (which sign with the user's own Apple ID
at install time):

```sh
./scripts/build-altstore-ipa.sh
# -> build/altstore/gterm-<version>-<build>.ipa  (+ .size, .sha256)
```

Then:

1. Create a GitHub Release tagged `v<version>-<build>` and attach the `.ipa`.
2. Update `docs/altstore.json` — paste the new `version`, `buildVersion`,
   `downloadURL`, `size`, and `sha256` into the leading `versions` entry
   (or prepend a new one to keep history).
3. Commit & push so GitHub Pages serves the refreshed manifest at
   `https://madeye.github.io/gterm/altstore.json`.

The AltStore landing page lives at `docs/altstore/index.html`.

## License

gterm is released under the [MIT License](LICENSE) © 2026 Max Lv.

Bundled / dependency components keep their own licenses: the
[ghostty](https://github.com/madeye/ghostty) engine is MIT; swift-nio-ssh,
swift-crypto, and swift-nio are Apache-2.0; the OpenAI and SwiftAnthropic SDKs
are MIT.


