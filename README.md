# gterm

An iOS terminal app that renders with [ghostty](../ghostty)'s `libghostty`
engine (GPU/Metal, full xterm/VT emulation) and connects over **SSH**.

> 📲 **Get the app:** [Download on the App Store](https://apps.apple.com/us/app/gterm-ghostty-ssh/id6774837597) (iOS 17+).
> Or sideload with [**AltStore** or **SideStore**](https://madeye.github.io/gterm/altstore/) — both read the same source URL `https://madeye.github.io/gterm/altstore.json`.

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

## iPad, iPhone Duo, and Magic Keyboard

On iPad, Hosts stays in a collapsible sidebar beside the terminal. Use the
Sessions menu to switch connections without disconnecting them. Keys, AI,
and Settings open in sheets; narrow windows collapse to one column.

iPhone Duo gets the same sidebar workspace on its inner display, where the
window is regular in both size classes. The outer display and Split View use
the iPhone tab layout. Sessions stay connected across folding; the terminal
surface simply moves between the two layouts. Full edge-to-edge use of the
inner display requires a build against the iOS 27.1 SDK.

Magic Keyboard supports two-finger scrollback, pointer drag selection, and
Command-click to open terminal links. The keyboard button hides the software
keyboard while keeping physical keyboard input focused on the terminal.
Hold Command to discover these terminal shortcuts:

| Shortcut | Action |
| --- | --- |
| Command-C / V / A | Copy selection / paste / select all |
| Command-= / - / 0 | Increase / decrease / reset font size |
| Command-Shift-] / [ | Next / previous session |
| Command-W | Return to Hosts, keeping the connection alive |

Control and Option combinations continue to go to the remote terminal,
including Control-C, Control-D, and Option word navigation. Right-click a
host to connect, edit, disconnect, or delete it.

Run the iPad UI tests offscreen (requires `paramiko` in your Python environment
and an installed iOS 26+ simulator runtime):

```sh
python3 scripts/test-ipad-ui.py
```

The runner creates a disposable iPad, boots it without opening Simulator.app,
starts the loopback SSH fixture, and runs all UI tests. It removes its device
and stops its fixture on completion or interruption. Existing simulators are
left alone. Logs and the `.xcresult` bundle (including screenshots) remain in
the printed temporary directory. Use `--derived-data PATH` to reuse a build cache.
`--device-type NAME` picks another simulator: `"iPhone 17 Pro Max"` runs the
phone layout tests (the iPad window test skips itself), and the iPhone Duo
simulator can be targeted the same way once Xcode 27.1 is installed.
`--only-testing gtermUITests/PhoneLayoutTests` narrows the run.

Port 62222 must be free for the fixture. The keyboard test exercises an SSH
connection, keyboard dispatch with the software keyboard hidden, session
switching, and rotation. The fixture reports input as hex: Control-C is `03`,
Control-D is `04`, and Option-X is `1b78`. Command shortcuts should not appear
in the SSH input. This is an SSH echo fixture, not a remote shell. Physical
trackpad feel and Magic Keyboard hardware still require a device smoke test.

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

## Testing SSH startup

Run the Herdr auto-attach regressions on macOS (no SSH credentials or running
Herdr server required):

```sh
xcodegen generate
xcodebuild -project gterm.xcodeproj -scheme gtermSSHTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

These tests exercise the PTY handler's request/reply flow and execute its
startup command with isolated shell profiles and a fixture `herdr` executable.
They cover PATH initialization, request failures, nonzero exit status, clean
detach, and terminal input/output. Channel tests also run in the iOS
`gtermTests` scheme; testing attachment to a real remote Herdr session still
requires a simulator or device smoke test.

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
