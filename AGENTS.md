# guidelines

1. if a code comment explains how instead of why its unncessary, your code is too complicated, delete the comment and make the code better
2. Do not refer to local files and folders in you code comments for example, the comment below is a bad comment because it refers to ../ghostty
   > # Builds libghostty from ../ghostty (branch flow-build: v1.3.1 + two Xcode 27)
3. if you have fixed something in the terminal, close the old debug build if running, and start a new one.
4. every keyboard shortcut Flow adds must be listed in the Keyboard Shortcuts window (the ? button in the title bar). The list is written by hand in `KeyboardShortcuts.all`, so add the new shortcut there whenever you add, change or remove one, named for what it does and in the section it belongs to. Open the window to check it, and add the shortcut to the site's keyboard shortcuts page at the next release.

# releases

Before cutting a release, update the website. It lives in the `thetinygoat/getflowterm.app` repo; if you don't know where it is checked out, ask. Its own AGENTS.md says how to build and deploy it.

1. Write the changelog entry in `src/content/changelog/<version>.md`, covering every user-facing change since the last release (`git log v<last>..HEAD`). Copy the front matter of the previous entry.
2. Add or update docs in `src/content/docs/` for the features that need them (see below).
3. Write and revise both with the `/unslop` skill.
4. Start the site's dev server, give the user the links to the new changelog entry (the page and its `.md`) and any docs you changed, and work their feedback in. Deploy only once they are happy.
5. Deploy the site before `scripts/release.py <version> --publish`. Flow's update dialog loads `/changelog/<version>.md`, and publishing refuses to run until it is live.

## changelog

Follow the Changelog section of the site's AGENTS.md. The changelog is mechanical: a grouped list of what changed, never a story. Fixes and internal changes belong there, never in the docs.

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
