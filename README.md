# gterm

An iOS terminal app that renders with [ghostty](../ghostty)'s `libghostty`
engine (GPU/Metal, full xterm/VT emulation) and connects over **SSH**.

iOS can't `fork`/`exec` a local shell, so gterm drives the terminal from an SSH
connection via a custom **passthru IO backend** added to libghostty. See
[PLAN.md](PLAN.md) for the full architecture.

## Status

- ✅ libghostty `passthru` IO backend (in `../ghostty`, branch
  `feature/libghostty-passthru-io`)
- ✅ iOS app scaffold; ghostty terminal surface renders on device/simulator
- ✅ Lean Swift layer (app, surface view, input) with a local-echo loopback
- ⏳ SSH transport (swift-nio-ssh), custom keyboard, connection management

## Building

Requirements: macOS, Xcode 26+, and the patched Homebrew zig:

```sh
brew install zig@0.15        # keg-only; the build script uses it by full path
brew install xcodegen
```

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

## Notes for this machine

The engine build needs the patched `zig@0.15` (the generic `zig` 0.15.2 hits a
Zig-0.15 + Xcode-26.4 linker bug) and an unset HTTP proxy (the harness proxy
breaks zig's package fetch). The build script handles the proxy; it defaults to
`/opt/homebrew/opt/zig@0.15/bin/zig` (override with `ZIG=...`).
