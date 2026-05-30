#!/usr/bin/env bash
#
# Build GhosttyKit.xcframework (the libghostty terminal engine) for gterm.
#
# gterm renders its terminal using ghostty's libghostty engine, cross-compiled
# to a static-library xcframework with macOS + iOS-device + iOS-simulator
# slices. This script builds it from the bundled `ghostty` submodule and copies
# the result next to this repo so the Xcode project can link it.
#
# Toolchain quirks on this machine (see also the project memory):
#   * Must use the patched keg-only zig: /opt/homebrew/opt/zig@0.15/bin/zig
#     (the generic `zig` 0.15.2 hits the Zig-0.15 + Xcode-26.4 link bug:
#      `undefined symbol: _clock_gettime`, `_dispatch_*`, ...).
#     Install with: brew install zig@0.15
#   * The harness HTTP proxy ($HTTPS_PROXY) breaks zig's HTTP client, so we
#     unset all proxy vars before invoking zig.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTERM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Default to the in-repo `ghostty` submodule. Override with GHOSTTY_DIR to point
# at a separate checkout (e.g. for local engine development).
GHOSTTY_DIR="${GHOSTTY_DIR:-$GTERM_DIR/ghostty}"

ZIG="${ZIG:-/opt/homebrew/opt/zig@0.15/bin/zig}"

if [[ ! -x "$ZIG" ]]; then
  echo "error: patched zig not found at $ZIG" >&2
  echo "       install it with: brew install zig@0.15" >&2
  exit 1
fi

if [[ ! -d "$GHOSTTY_DIR" || -z "$(ls -A "$GHOSTTY_DIR" 2>/dev/null)" ]]; then
  echo "error: ghostty submodule not checked out at $GHOSTTY_DIR" >&2
  echo "       run: git submodule update --init ghostty" >&2
  echo "       (or set GHOSTTY_DIR=/path/to/ghostty for a separate checkout)" >&2
  exit 1
fi

echo "==> Building GhosttyKit.xcframework"
echo "    ghostty: $GHOSTTY_DIR"
echo "    zig:     $ZIG ($("$ZIG" version))"

NOPROXY=(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy)

cd "$GHOSTTY_DIR"

# Fetch the FULL dependency tree first (including lazy deps like libxev) so we
# can patch libxev before it compiles. `--fetch` alone uses "needed" mode and
# skips lazy deps, which would leave libxev unpatched and crash on iOS.
echo "==> Fetching dependencies"
"${NOPROXY[@]}" "$ZIG" build --fetch=all

# Patch libxev for iOS. libxev's kqueue backend only wires up its mach-port
# based Async ("wakeup") for macOS; on iOS it returns null from kevent() and
# then unwrap-panics. iOS supports mach ports + EVFILT_MACHPORT just like
# macOS, so we widen the gates from `.macos` to any Darwin. Without this,
# ghostty's renderer/termio/cf-release threads crash on iOS. This is applied
# idempotently to the (content-addressed) zig cache copy.
patch_libxev() {
  local found=0 ok=0 kq
  for kq in "$HOME"/.cache/zig/p/libxev-*/src/backend/kqueue.zig; do
    [ -f "$kq" ] || continue
    found=1
    if grep -q 'builtin.os.tag != .macos) return null else kevent' "$kq"; then
      sed -i '' \
        -e 's/\.machport => if (comptime builtin\.os\.tag != \.macos) return null else kevent/.machport => if (comptime !builtin.os.tag.isDarwin()) return null else kevent/' \
        -e 's/if (comptime builtin\.target\.os\.tag == \.macos) {/if (comptime builtin.target.os.tag.isDarwin()) {/' \
        "$kq"
      echo "    patched libxev for iOS: $kq"
    fi
    # Verify the file is now in the patched state (either we just patched it,
    # or it was already patched).
    if grep -q 'isDarwin()) return null else kevent' "$kq"; then ok=1; fi
  done
  if [ "$found" -eq 0 ]; then
    echo "error: libxev not found in zig cache after fetch; cannot apply iOS patch" >&2
    exit 1
  fi
  if [ "$ok" -eq 0 ]; then
    echo "error: libxev iOS patch did not apply (kqueue.zig not in expected form)" >&2
    exit 1
  fi
}
echo "==> Patching libxev for iOS (mach-port Async)"
patch_libxev

echo "==> Compiling"
"${NOPROXY[@]}" "$ZIG" build -Demit-macos-app=false "$@"

SRC="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
DST="$GTERM_DIR/GhosttyKit.xcframework"

if [[ ! -d "$SRC" ]]; then
  echo "error: expected xcframework not produced at $SRC" >&2
  exit 1
fi

echo "==> Syncing xcframework into gterm"
rm -rf "$DST"
cp -R "$SRC" "$DST"

echo "==> Done. Slices:"
ls -1 "$DST"
