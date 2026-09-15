# Repository Guidelines

## Project Structure & Module Organization

`gterm` is an iOS SwiftUI SSH terminal app backed by Ghostty's rendering engine. Source lives under `Sources/`:

- `Sources/App/`: app entry point.
- `Sources/UI/`: SwiftUI screens and connection/key management views.
- `Sources/Ghostty/`: Swift bridge and terminal surface/input integration.
- `Sources/SSH/`: `swift-nio-ssh` transport, PTY channel, known-host handling, and key parsing.
- `Sources/Terminal/` and `Sources/Model/`: terminal protocol abstractions, persistence, and Keychain helpers.

`project.yml` is the XcodeGen source of truth. `gterm.xcodeproj`, `Info.plist`, and `GhosttyKit.xcframework` are generated and ignored. `scripts/build-ghostty-xcframework.sh` builds the Ghostty engine from a sibling `../ghostty` checkout.

## Build, Test, and Development Commands

- `./scripts/build-ghostty-xcframework.sh`: build and copy `GhosttyKit.xcframework`. Requires patched Homebrew `zig@0.15`; override with `ZIG=...` or `GHOSTTY_DIR=...`.
- `xcodegen generate`: regenerate `gterm.xcodeproj` and generated app metadata from `project.yml`.
- `xcodebuild -project gterm.xcodeproj -scheme gterm -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`: compile the app for simulator without signing.
- Open `gterm.xcodeproj` in Xcode for simulator/device runs after regeneration.

## Coding Style & Naming Conventions

Use Swift 5 language mode, four-space indentation, and existing Swift API naming. Types use `UpperCamelCase`; methods, properties, and enum cases use `lowerCamelCase`. Keep UI code in `Sources/UI`, SSH/networking code in `Sources/SSH`, and C/Ghostty interop isolated in `Sources/Ghostty`. Prefer small, explicit types and avoid blocking callbacks from Ghostty or NIO threads; hop to the appropriate event loop or main thread.

## Testing Guidelines

Three test targets exist, all defined in `project.yml`: `gtermTests` (logic-only, compiles `Sources/LLM` + `Tests/`, run with `xcodebuild -scheme gtermTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`), `gtermSSHTests` (macOS), and `gtermUITests` (XCUITest, `UITests/`). Run the UI suite offscreen with `python3 scripts/test-ipad-ui.py` (needs `paramiko`; `--device-type NAME` targets another simulator such as `"iPhone 17 Pro Max"` or the iPhone Duo). Every change should at least pass the simulator build command above. For behavior touching SSH auth, host-key trust, terminal input, resize, or Keychain persistence, also do a manual simulator/device smoke test. Name test files after the feature under test, for example `SSHKeyParserTests.swift`.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative subjects with the `gterm:` prefix, for example `gterm: SSH private-key management`. Keep commits focused and mention generated artifacts only when the source file that produces them changed. PRs should describe the user-visible behavior, list build/manual verification, link related issues, and include screenshots or short recordings for UI changes.

## Security & Configuration Tips

Do not commit secrets, private keys, provisioning material, or local config. `.gitignore` already excludes `*.p8`, `local.properties`, `secrets.xcconfig`, generated build output, and `GhosttyKit.xcframework`. Store SSH passwords and imported keys through the app's Keychain paths, not in source fixtures or logs.
