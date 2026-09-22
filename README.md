# flow

A macOS terminal built on libghostty. Sidebar of workspaces, tabs and panes inside each.

## Build

Requires Xcode 27, Zig 0.15.2, and xcodegen (`brew install xcodegen`).

```
git clone --recursive <repo> flow && cd flow
./scripts/build-ghosttykit.sh   # builds libghostty from Vendor/ghostty, stages Vendor/ (slow, once)
xcodegen generate               # writes flow.xcodeproj from project.yml
open flow.xcodeproj             # or: xcodebuild -scheme flow -configuration Debug build
```

`Vendor/ghostty` is a git submodule pinned to Ghostty's latest stable release.
`patches/` holds upstream build fixes needed for Xcode 27 that landed after that release.
The build script applies them.

## Tests

```
xcodebuild test -scheme flow -destination 'platform=macOS'
```

The test bundle compiles the model sources directly and does not launch the app.

## Layout

- `Sources/Ghostty/` wraps the libghostty C API: runtime, config, input mapping, surface view.
- `Sources/Workspace/` is the workspace, tab, and pane model, generic over a `PaneLeaf` so tests run without terminals.
- `Tests/` holds unit tests for the model.
- `Sources/UI/` is the AppKit window: sidebar on the left, terminal area on the right.
- `Vendor/GhosttyKit.xcframework` and `Vendor/GhosttyResources` are build outputs, not committed.
