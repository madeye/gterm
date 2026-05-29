# gterm — iOS SSH Terminal (built on ghostty)

`gterm` is an iOS terminal application that renders a real terminal using
[ghostty](../ghostty)'s `libghostty` engine (GPU/Metal rendering, full VT/xterm
emulation, ligatures, Kitty keyboard protocol, etc.) and drives it over **SSH**
instead of a local shell — because iOS cannot `fork`/`exec` a subprocess.

## Goals

1. Render terminals with ghostty's actual engine (not a reimplementation).
2. Connect to remote hosts over SSH with an interactive PTY shell.
3. First-class mobile UX: a custom in-app accessory keyboard (Esc, Ctrl, Alt,
   Tab, arrows, Fn, pipe/slash/dash/tilde, sticky modifiers).
4. Connection management (hosts, password & key auth, host-key trust).

## Architecture

```
┌─────────────────────────── gterm (iOS app, Swift) ───────────────────────────┐
│  SwiftUI shell: Connection list → Terminal screen                             │
│                                                                               │
│  ┌── TerminalView (UIView) ──────────┐    ┌── SSHSession (swift-nio-ssh) ──┐  │
│  │  CAMetalLayer  ← libghostty draws  │    │  TCP → SSH transport           │  │
│  │  ghostty_surface_t (passthru IO)   │    │  user-auth (pw / publickey)    │  │
│  │  UIKeyInput / key commands         │    │  PTY child channel:            │  │
│  │  touch: scroll / selection         │    │   pty-req + shell + win-change │  │
│  └────────────┬───────────────────────┘    └───────────┬────────────────────┘ │
│               │ outgoing bytes (queueWrite cb)          │ channel.writeAndFlush │
│               │ ───────────────────────────────────────▶                       │
│               │ incoming bytes (ghostty_surface_pty_data)                       │
│               ◀─────────────────────────────────────────                       │
│               │ resize cb → WindowChangeRequest ───────▶                        │
│  + AccessoryKeyboard (input accessory view) → ghostty_surface_key / _text      │
└───────────────────────────────────────────────────────────────────────────────┘
        │ links (static)
        ▼
  GhosttyKit.xcframework  ←  built from ../ghostty (modified: passthru backend)
```

### Why a new "passthru" termio backend (the crux)

libghostty's `Surface` owns IO through one backend — `exec` — which fork/execs a
shell on a PTY (`src/termio/backend.zig`, `src/termio/Exec.zig`). iOS forbids
that, and the C API offers no way to feed bytes from a network source. So we add
a **`passthru`** backend to ghostty that owns no process:

- **Incoming (SSH → terminal):** new C API
  `ghostty_surface_pty_data(surface, ptr, len)` → `Termio.processOutput(buf)`
  (`Termio.zig:643`, the documented manual ingress also used by exec's read
  thread; thread-safe — it takes the renderer lock).
- **Outgoing (terminal → SSH):** every terminal→pty write funnels through
  `Termio.queueWrite` → `backend.queueWrite` (verified at `Thread.zig:336-348`).
  The passthru backend's `queueWrite` is the single chokepoint → invokes an
  app-provided callback with the bytes; gterm forwards them to the SSH channel.
- **Resize → SSH:** passthru `resize(grid, screen)` → app callback with
  cols/rows → gterm sends `WindowChangeRequest`.

Backend is selected by a new `io_backend` field on `ghostty_surface_config_s`;
the write/resize callbacks ride on the surface config. `Surface.zig` branches to
skip subprocess creation when passthru is selected.

## Components & build order

### Phase 1 — libghostty `passthru` backend (Zig, in ../ghostty)
Files: `src/termio/backend.zig` (+`passthru` variant), **new** `src/termio/Passthru.zig`,
`src/termio.zig` (export), `src/Surface.zig` (branch backend creation),
`src/apprt/embedded.zig` (Surface.Options fields + `ghostty_surface_pty_data`
export + config plumbing), `include/ghostty.h` (`ghostty_io_backend_e`,
config fields, function decl). Validate: `zig build -Demit-macos-app=false`
produces the xcframework; add a Zig test that pushes bytes through processOutput
and asserts queueWrite callback receipt.

### Phase 2 — xcframework + Xcode project skeleton
`scripts/build-ghostty-xcframework.sh` (done) → `GhosttyKit.xcframework`.
Generate `gterm.xcodeproj` (iOS app target, deploy 17.0, links GhosttyKit + Metal/
MetalKit/QuartzCore/CoreText/CoreGraphics, `-ObjC -lstdc++`, SPM: swift-nio-ssh).
App boots, shows an empty terminal surface, `ghostty_app_tick` on a CADisplayLink.

### Phase 3 — lean Swift ghostty layer
`GhosttyApp.swift` (init/app/tick + runtime callbacks; implement iOS action_cb:
title/bell/clipboard), `TerminalSurfaceView.swift` (UIView, CAMetalLayer, size/
scale/focus, passthru callbacks ↔ delegate), `GhosttyInput.swift` (trimmed port of
Key/Mods/KeyEvent). Verify locally with a loopback "echo" data source before SSH.

### Phase 4 — SSH transport (swift-nio-ssh)
`SSHSession.swift` (connect, user-auth delegate password+publickey, server-auth/
known-hosts delegate), `PTYChannelHandler.swift` (pty-req xterm-256color + shell +
window-change; inbound channel data → surface; surface outgoing → channel).
Wire resize callback → WindowChangeRequest.

### Phase 5 — custom accessory keyboard
`AccessoryKeyboardView.swift`: rows for Esc/Ctrl/Alt/Tab/arrows/Home/End/PgUp/PgDn/
Del/Fn and symbol keys; sticky Ctrl/Alt; special keys → `ghostty_surface_key`
(mode-aware), printable → `ghostty_surface_text`. Hardware-keyboard support via
`UIKey`/`pressesBegan` → HID→ghostty key map.

### Phase 6 — connection management & polish
Host store (Keychain for secrets), add/edit connection, key import, host-key
trust-on-first-use prompt, reconnect, font/theme settings, scrollback gestures.

## Key risks & mitigations
- **C/Zig struct ABI sync** — keep `ghostty.h` and `embedded.zig` `Surface.Options`
  in lock-step; add fields at the end; consider a compile-time size assertion.
- **Callback threading** — passthru callbacks fire on ghostty's io thread; gterm
  must hop to the NIO event loop (SSH) / main thread (UI) and never block.
- **Upstream divergence** — keep the ghostty change minimal & self-contained on a
  branch so it can be rebased; everything else lives in gterm.
- **App Store** — pure-Swift SSH (swift-nio-ssh), no private APIs.

## Toolchain (confirmed working)
Xcode 26.4, iOS 26.4 SDK, patched `zig@0.15` (`/opt/homebrew/opt/zig@0.15/bin/zig`).
Build needs proxy env unset (harness `HTTPS_PROXY` breaks zig's fetch). The
unmodified xcframework already cross-compiles for iOS — verified end to end.
