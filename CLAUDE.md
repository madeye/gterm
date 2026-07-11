# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is gterm

gterm is an iOS terminal app that renders using ghostty's `libghostty` engine (GPU/Metal, full VT/xterm emulation) and connects over SSH via swift-nio-ssh. iOS can't `fork`/`exec`, so gterm uses a custom **passthru IO backend** added to a fork of ghostty — the terminal surface is driven entirely by bytes arriving over an SSH channel.

## Build Commands

### Prerequisites

```sh
brew install zig@0.15    # keg-only patched zig
brew install xcodegen
git submodule update --init ghostty   # if not already checked out
```

### Build the terminal engine (one-time, or when ghostty submodule changes)

```sh
./scripts/build-ghostty-xcframework.sh
```

Produces `GhosttyKit.xcframework` (macOS + iOS device + iOS simulator slices). Requires the patched `/opt/homebrew/opt/zig@0.15/bin/zig`; proxy env vars must be unset (the script handles this). Override with `ZIG=...` or `GHOSTTY_DIR=...`.

### Generate Xcode project and build

Signing config (team id, ASC key) lives in a git-ignored `.env` — copy
`env.example` to `.env` and fill it in once. Source it before `xcodegen`
so `${DEVELOPMENT_TEAM}` in `project.yml` expands (not needed for
`CODE_SIGNING_ALLOWED=NO` simulator/test builds):

```sh
set -a; source .env; set +a
xcodegen generate
xcodebuild -project gterm.xcodeproj -scheme gterm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Or open `gterm.xcodeproj` in Xcode after `xcodegen generate`.

### Run tests

```sh
xcodegen generate
xcodebuild -project gterm.xcodeproj -scheme gtermTests \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

The `gtermTests` target compiles only `Sources/LLM` + `Tests/` — no GhosttyKit or UIKit dependency, so tests are fast and hermetic.

### Build unsigned IPA (AltStore/SideStore sideloading)

```sh
./scripts/build-altstore-ipa.sh
# → build/altstore/gterm-<version>-<build>.ipa
```

### App Store metadata

```sh
set -a; source .env; set +a        # Appfile/Deliverfile read team + key from env
fastlane deliver                   # uploads metadata + screenshots from fastlane/metadata/
```

## Generated / git-ignored artifacts

`gterm.xcodeproj`, `Info.plist`, and `GhosttyKit.xcframework` are all generated and in `.gitignore`. The source of truth for the Xcode project is `project.yml` (XcodeGen). Always run `xcodegen generate` after modifying `project.yml`.

## Architecture

### Source modules (`Sources/`)

| Module | Purpose |
|--------|---------|
| `App/` | SwiftUI app entry point (`GTermApp.swift`) |
| `Ghostty/` | Swift bridge to libghostty: `GhosttyApp` (app lifecycle + CADisplayLink tick), `TerminalSurfaceView` (UIView + CAMetalLayer + passthru callbacks), `GhosttyInput` (key/mod mapping), `AccessoryKeyboardView` (on-screen Esc/Ctrl/Alt/Tab/arrows), `GhosttyConfig` (theme/font), extensions for scroll, selection, link detection, hardware keyboard, and inline completions |
| `SSH/` | `SSHSession` (swift-nio-ssh connect, password + public-key auth, PTY channel, window-change), `PTYChannelHandler`, `GlueHandler`, `SSHKeyParser`, `KnownHosts` (TOFU), `PortForwardManager` |
| `Terminal/` | `TerminalSession` protocol — the abstraction between a surface view and its byte source/sink. `SSHSession` and `LoopbackSession` both conform. |
| `LLM/` | Pure Foundation (no UIKit/GhosttyKit) — LLM autocompletion core: `LLMProvider` (OpenAI + Anthropic SDK wrappers), `Completion` (policy, prompt factory, sanitizer), `CommandAssistant`, `ProviderProfile`. This module is compiled standalone in the test target. |
| `Model/` | Persistence & engines: `ConnectionStore`, `KeyStore`, `PortForwardStore`, `ProviderStore`, `Keychain`, `CompletionEngine` (debounced LLM requests), `CommandAssistantEngine`, `CommandHistory` |
| `UI/` | SwiftUI screens: connection list, add/edit connection, terminal screen, key management, AI settings, onboarding, port-forward UI, settings, theme picker, browser |
| `Browser/` | In-app `WKWebView` for tunneled port-forward HTTP |

### The passthru data flow (the crux of the design)

```
SSH channel data → SSHSession.channelRead → TerminalSurfaceView.receive(_:)
    → ghostty_surface_pty_data() → libghostty renders on CAMetalLayer

User keystroke → ghostty encoder → passthru queueWrite callback
    → TerminalSurfaceView.didProduceOutput → SSHSession → SSH channel.write

Terminal resize → passthru resize callback → SSHSession → WindowChangeRequest
```

Passthru callbacks fire on ghostty's IO thread — always hop to the NIO event loop (SSH) or main thread (UI) and never block.

### C interop

GhosttyKit is a static Zig library linked with `-ObjC -lstdc++`. The `Ghostty/` module uses `Unmanaged`, C function-pointer callbacks, and raw struct access against `ghostty.h`. The project uses **Swift 5 language mode** because this low-level interop is substantially simpler than under Swift 6 strict concurrency.

## Coding Conventions

- Swift 5, four-space indentation, standard Swift API naming
- Commit messages use `gterm:` prefix, imperative mood (e.g. `gterm: add port-forward UI`)
- UI code in `Sources/UI`, SSH/networking in `Sources/SSH`, C/Ghostty interop in `Sources/Ghostty`
- Keep the `Sources/LLM` module free of UIKit/GhosttyKit imports so it stays testable standalone

## Project Configuration

- Bundle ID: `io.github.madeye.gterm`
- Deployment target: iOS 17.0
- Team: from `DEVELOPMENT_TEAM` in the git-ignored `.env` (see `env.example`); App Store Connect only accepts builds signed by the current team there — the old `SK4GFF6AHN` team is stale
- Version/build: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
- Dependencies: swift-nio-ssh, swift-crypto, OpenAI (MacPaw), SwiftAnthropic
- CI: `.github/workflows/build.yml` — builds the engine on macOS-15, caches `~/.cache/zig`
