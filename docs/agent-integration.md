# Agent integration

Flow learns what coding agents (Claude Code, Codex, …) are doing in its
terminals and shows it: which workspace is working, which one is waiting for
you, which one just finished. Later, the same data lets Flow resume agent
sessions after a relaunch.

This document is the design. It starts with Claude Code and Codex, and is
built so adding an agent means adding one adapter, nothing else.

## How it works

```
agent process ──hook──▶ flw ──unix socket──▶ Flow app ──▶ AgentSession store ──▶ UI
```

1. The agent reaches a lifecycle point (a prompt was submitted, a tool is
   about to run, the turn ended). It looks up the hooks registered for that
   event, starts a process for each, and writes the event as JSON to the
   process's stdin.
2. That process is `flw hook <agent>`. It reads the JSON, translates it into
   Flow's own event shape, writes one line to Flow's socket, and exits 0.
3. Flow's socket listener parses the line, binds the event to the terminal
   the agent is running in, and updates that terminal's `AgentSession`.
4. The UI renders from the store: workspace rows, notifications, and later
   session restore.

Hooks are registered as `async`, and `flw` exits 0 on every path, so Flow can
never slow down or block an agent.

## The event model

Everything above the adapters speaks one vocabulary:

```swift
struct AgentEvent {
    let agent: AgentKind        // .claudeCode, .codex
    let sessionID: String       // the agent's own id, used for resume
    let surfaceID: UUID?        // the Flow terminal, from FLOW_SURFACE_ID
    let cwd: String
    let at: Date
    let kind: Kind

    enum Kind {
        case sessionStarted
        case turnStarted                    // the user submitted a prompt
        case working(detail: String?)       // tool use; detail is the tool name
        case needsInput(reason: String)     // permission prompt, question, idle prompt
        case turnEnded(summary: String?)    // the agent's last message
        case sessionEnded
    }
}
```

Adapters only produce these. New agents never touch the app.

## Adapters

An adapter has two jobs: install the agent's hook config, and translate the
agent's native events.

| | Claude Code | Codex |
|---|---|---|
| Config file | `~/.claude/settings.json` | `~/.codex/hooks.json` |
| Hook command | `flw hook claude` | `flw hook codex` |
| sessionStarted | `SessionStart` | `SessionStart` |
| turnStarted | `UserPromptSubmit` | `UserPromptSubmit` |
| working | `PreToolUse`, `PostToolUse` (`tool_name`) | `PreToolUse`, `PostToolUse` |
| needsInput | `Notification` with `notification_type` in `permission_prompt`, `idle_prompt`, `agent_needs_input`, `elicitation_*` | `PermissionRequest` |
| turnEnded | `Stop` (`last_assistant_message`) | `Stop`, `Interrupt` |
| sessionEnded | `SessionEnd` | `SessionEnd` |
| Common stdin fields | `session_id`, `cwd`, `hook_event_name`, `transcript_path` | `session_id`, `cwd`, `hook_event_name`, `turn_id` |

Both configs have the same JSON shape: event → list of `{ matcher?, hooks: [ { type: "command", command, async } ] }`.
Codex asks the user once to trust newly installed hooks (its `/hooks`
command); setup tells the user so.

## Installing hooks

`flw agents setup [agent]` merges Flow's hooks into the agent's config file:

- Read and parse the file (`{}` if missing). Refuse to touch a file that is
  not valid JSON.
- Keep every existing key. Under `hooks`, append one entry per event whose
  command is `flw hook <agent>`. Other hooks stay as they are.
- Idempotent: Flow's entries are recognised by their command, so setup
  updates them instead of duplicating, and `flw agents uninstall` removes
  exactly those.
- Write a backup (`<file>.flow-backup`), then write atomically.
- Setup is always an explicit user action (menu item or command), never
  automatic at launch.

The hook config points at a stable path, `~/.local/bin/flw`, a symlink to
`Flow.app/Contents/Helpers/flw` that Flow refreshes at launch. Moving the app
does not break the hooks.

## Binding an event to a terminal

Never by guessing. In order:

1. `FLOW_SURFACE_ID` and `FLOW_WORKSPACE_ID`, which Flow injects into every
   shell it spawns. A hook process is a child of the agent, which is a child
   of that shell, so it inherits them. A hand-typed `claude` is covered.
2. The hook process's controlling tty, mapped to the terminal that owns it.
3. The hook process's ancestry, mapped to the terminal whose shell is its
   ancestor.

Surface ids are minted once, saved in the session file, and reused on
restore, so bindings and resume data survive a relaunch.

## The socket

- Path: `~/Library/Application Support/flow/agent.sock`, mode 0600.
- Protocol: one JSON object per line, the encoded `AgentEvent` plus the raw
  native payload for debugging. Fire and forget in v1; the connection is
  kept open only as long as the write takes.
- If Flow is not running, `flw` exits 0 without complaint.
- Parsing happens off the main thread; the store receives finished values.

Two-way use (Flow answering a `PermissionRequest` from its own UI) is a
later extension of the same protocol.

## State in the app

One `AgentSession` per terminal:

```
idle ──turnStarted──▶ working ──needsInput──▶ waiting ──turnStarted/working──▶ working
  ▲                      │                                                   │
  └──────turnEnded───────┘◀──────────────────────────────────────────────────┘
any ──sessionEnded / shell exited──▶ ended
```

Rules, learned from cmux:

- Push is a hint, the store is the truth. The UI renders from the store.
- Delivery is not guaranteed. A missed `Stop` must not leave a terminal
  "working" forever: the shell process exiting ends the session, and a new
  `sessionStarted` on the same terminal replaces the old session.
- `ended` sessions are kept, not deleted, so their resume data is still there.

What the store drives:

- Workspace rows: working, waiting for you, finished but not yet seen.
- Notifications when the terminal is not in view: `needsInput` ("Claude
  needs your input"), `turnEnded` with the agent's last message.
- Later: `claude --resume <id>` / `codex resume <id>` when restoring a
  session, with a sanitised launch command.

## Agents without hooks

Flow prepends a shim directory to `PATH` in its shells. A shim named after
the agent emits `sessionStarted` itself (surface, cwd, child pid), execs the
real binary, and emits `sessionEnded` when it exits. State in between comes
from the process tree and, where the agent writes a transcript, from tailing
it. Nothing above the adapter changes.

## Build order

1. Inject `FLOW_SURFACE_ID` / `FLOW_WORKSPACE_ID`; persist surface ids.
2. The `flw` tool target, the socket listener, the event model, unit tests.
3. Claude Code adapter and setup, tested with real hook payloads.
4. Codex adapter and setup.
5. Workspace row state and notifications from the store.
6. Session resume.
