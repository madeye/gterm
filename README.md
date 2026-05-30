# gterm

An iOS terminal app that renders with [ghostty](../ghostty)'s `libghostty`
engine (GPU/Metal, full xterm/VT emulation) and connects over **SSH**.

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
   local shell). Clone it next to this repo:

   ```sh
   git clone https://github.com/madeye/ghostty.git ../ghostty
   ```

   (Or clone it elsewhere and pass `GHOSTTY_DIR=/path/to/ghostty` to the build
   script below.)

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


