<p align="center">
  <img src="docs/icon.svg" width="96" height="96" alt="Flow icon">
</p>

<h1 align="center">Flow</h1>

<p align="center">A calmer, more productive terminal.</p>

<p align="center">
  <a href="https://github.com/thetinygoat/flow/releases/latest">Download</a>
  ·
  <a href="https://getflowterm.com/docs/getting-started/">Docs</a>
  ·
  <a href="https://getflowterm.com/changelog/">Changelog</a>
</p>

A fast, native terminal built on Ghostty, for everyday work. Run a fleet of agents or just a shell. Flow stays deliberately minimal and simple, with no accounts and no telemetry.

## Why Flow?

**Native and fast.** Flow is a Swift and AppKit app powered by libghostty. There is no Electron and no web view.

**Agent integration (coming soon).** First-class support for AI agents like Claude Code, Codex and others.

**Private and simple.** No account, no telemetry, no tracking. Your terminal is yours.

## Install

Flow needs macOS 14 or later.

1. Download the latest `.dmg` from [releases](https://github.com/thetinygoat/flow/releases/latest).
2. Open it and drag Flow into Applications.
3. Open Flow.

Flow updates itself.

## Getting around

Each project gets its own workspace in the sidebar, with its own tabs and split panes. Flow reopens everything as you left it.

| Shortcut | Action |
| --- | --- |
| <kbd>⌘</kbd><kbd>N</kbd> | New workspace |
| <kbd>⌘</kbd><kbd>T</kbd> | New tab |
| <kbd>⌘</kbd><kbd>D</kbd> | Split right |
| <kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd> | Switch workspace |

Hold <kbd>⌘</kbd> to see the shortcut for each workspace. The [docs](https://getflowterm.com/docs/keyboard-shortcuts/) list the rest.

## Configuration

Flow has no config file of its own. It reads your Ghostty config, so your fonts, themes and keybindings carry over. Choose **Flow › Settings…** to open it.

Flow aims to support every Ghostty setting, but some don't work in Flow yet. If a setting you rely on has no effect, [open an issue](https://github.com/thetinygoat/flow/issues/new).

## Build from source

You need Xcode 27, Zig 0.15.2 and xcodegen (`brew install xcodegen`).

```sh
git clone --recursive https://github.com/thetinygoat/flow.git && cd flow
./scripts/build-ghosttykit.sh   # builds libghostty, slow, only needed once
xcodegen generate               # writes flow.xcodeproj from project.yml
open flow.xcodeproj
```

To build without opening Xcode, run `xcodebuild -scheme flow -configuration Debug build`.

`Vendor/ghostty` is a git submodule pinned to Ghostty's latest stable release. `patches/` holds build fixes for Xcode 27 that landed upstream after that release, and the build script applies them.

### Tests

```sh
xcodebuild test -scheme flow -destination 'platform=macOS'
```

The tests compile the model sources directly and don't launch the app.

### Layout

| Directory | Contents |
| --- | --- |
| `Sources/Ghostty/` | The wrapper around libghostty's C API, with the runtime, config, input and terminal view |
| `Sources/Workspace/` | The workspace, tab and pane model. It's generic over `PaneLeaf`, so tests run without terminals. |
| `Sources/UI/` | The AppKit window, with the sidebar on the left and terminals on the right |
| `Tests/` | Unit tests for the model |

`Vendor/GhosttyKit.xcframework` and `Vendor/GhosttyResources` are build outputs and aren't committed.

## License

Flow is released under the [MIT License](LICENSE). Third-party licenses are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
