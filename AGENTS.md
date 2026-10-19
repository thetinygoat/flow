# guidelines

1. if a code comment explains how instead of why its unncessary, your code is too complicated, delete the comment and make the code better
2. Do not refer to local files and folders in you code comments for example, the comment below is a bad comment because it refers to ../ghostty
   > # Builds libghostty from ../ghostty (branch flow-build: v1.3.1 + two Xcode 27)
3. the vendor/ghostty directory will show as changed to git due to patches, ignore it.
4. if you have fixed something in the terminal, close the old debug build if running, and start a new one.

# releases

Before cutting a release, update the website. It lives in the `thetinygoat/getflowterm.app` repo; if you don't know where it is checked out, ask. Its own AGENTS.md says how to build and deploy it.

1. Write the changelog entry in `src/content/changelog/<version>.md`, covering every user-facing change since the last release (`git log v<last>..HEAD`). Copy the front matter of the previous entry.
2. Add or update docs in `src/content/docs/` for the features that need them (see below).
3. Write and revise both with the `/unslop` skill.
4. Deploy the site before `scripts/release.py <version> --publish`. Flow's update dialog loads `/changelog/<version>.md`, and publishing refuses to run until it is live.

## changelog

Write for someone who uses Flow, not someone who reads its code: what they saw before, what happens now, and anything they have to do. A short lead line, then a `##` heading per change. Fixes and internal changes belong here, never in the docs.

- Good: "Dragging a Flow window to an external display could quit Flow at once. The window now moves without trouble."
- Bad: "Keep titlebar accessory views frame-based so screen changes don't crash." (a commit message, about the code)
- Good: "Flow's Codex hooks changed, so Codex skips them until you trust them again: run `/hooks` in Codex and trust the Flow hooks."
- Bad: "Hooks are now synchronous." (true, but says nothing about what the user sees or must do)

## docs

A doc page is for something the user has to learn, set up or look up. Most changes don't need one.

- Needs docs: a new feature with behaviour to understand (agent status got `agents.md`), a step the user must take (trusting Codex hooks), a new setting or shortcut.
- No docs: bug fixes, polish (the sidebar scroll bar keeping its overlay style), internal changes (hooks becoming synchronous). The changelog covers them.
- Prefer extending a page to adding one: a new shortcut goes in `keyboard-shortcuts.md`, another supported agent goes in `agents.md`. A new page is for a new area of Flow, such as workspaces.

Write docs as what the user does and sees, not how Flow does it.

- Good: "Press ⇧⌘R to rename the current workspace."
- Bad: "The Workspace menu is built from the window's workspace list and binds ⇧⌘R to rename." (implementation)
- Good: "A yellow dot means the agent is waiting for you."
- Bad: "Flow maps the agent's Notification hook to a needsInput state." (only true from the inside, and changes with the code)
