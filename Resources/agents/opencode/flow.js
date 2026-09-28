// Flow loads this plugin into each OpenCode it starts, through
// OPENCODE_CONFIG_CONTENT, so nothing is written to the user's configuration.
// It reports the session's progress to Flow with `flw event`, and hands `flw`
// what the user and the model said, which `flw` keeps to name the session.
import { spawn } from "node:child_process"

const detailLimit = 200
// `flw` keeps less than this of each message; the cut only keeps its
// command line short.
const excerptLimit = 1000

function summary(text) {
  const line = text.split(/\s+/).filter(Boolean).join(" ")
  return line.length > detailLimit ? line.slice(0, detailLimit - 1) + "…" : line
}

export const Flow = async () => {
  const flw = process.env.FLOW_FLW
  if (!flw) return {}

  // Subagents run in child sessions, and would make their parent's state
  // flap while it waits on them.
  const children = new Set()
  const lastText = new Map()
  const excerpts = new Map()
  const busy = new Set()
  const live = new Set()
  // Flow orders events by when `flw` sends them, so each waits for the one before.
  let sent = Promise.resolve()

  function remember(sessionID, role, text) {
    if (!sessionID || children.has(sessionID) || !text?.trim()) return
    const pending = excerpts.get(sessionID) ?? []
    pending.push(`${role}: ${text.slice(0, excerptLimit)}`)
    excerpts.set(sessionID, pending)
  }

  function send(kind, sessionID, detail) {
    if (!sessionID || children.has(sessionID)) return
    live.add(sessionID)
    const args = ["event", kind, "--agent", "opencode", "--session", sessionID]
    if (detail) args.push("--detail", detail)
    for (const excerpt of excerpts.get(sessionID) ?? []) args.push("--excerpt", excerpt)
    excerpts.delete(sessionID)
    sent = sent.then(() => new Promise((resolve) => {
      try {
        const child = spawn(flw, args, { stdio: "ignore" })
        child.on("error", resolve)
        child.on("close", resolve)
      } catch {
        resolve()
      }
    }))
  }

  return {
    event: async ({ event }) => {
      const properties = event.properties ?? {}
      const sessionID = properties.sessionID ?? properties.info?.id
      switch (event.type) {
        case "session.created":
          if (properties.info?.parentID) children.add(sessionID)
          else send("sessionStarted", sessionID)
          break
        case "session.status":
          if (properties.status?.type !== "busy" || busy.has(sessionID)) break
          busy.add(sessionID)
          send("turnStarted", sessionID)
          break
        case "session.idle": {
          busy.delete(sessionID)
          const text = lastText.get(sessionID)
          remember(sessionID, "assistant", text)
          send("turnEnded", sessionID, text && summary(text))
          lastText.delete(sessionID)
          break
        }
        case "permission.asked":
          send("needsInput", sessionID, "permission")
          break
        case "question.asked":
          send("needsInput", sessionID, "question")
          break
        case "session.error": {
          const error = properties.error
          send("attention", sessionID, summary(String(error?.data?.message ?? error?.name ?? "error")))
          break
        }
        case "session.deleted":
          excerpts.delete(sessionID)
          send("sessionEnded", sessionID)
          live.delete(sessionID)
          children.delete(sessionID)
          break
      }
    },
    "tool.execute.before": async ({ tool, sessionID }) => {
      send("working", sessionID, tool)
    },
    // Quitting OpenCode deletes no sessions, so the ones it had open end here.
    dispose: async () => {
      for (const sessionID of live) send("sessionEnded", sessionID)
      live.clear()
      await Promise.race([sent, new Promise((resolve) => setTimeout(resolve, 1000))])
    },
    "experimental.text.complete": async ({ sessionID }, { text }) => {
      if (text?.trim()) lastText.set(sessionID, text)
    },
    "chat.message": async ({ sessionID }, { parts }) => {
      const text = (parts ?? [])
        .filter((part) => part.type === "text" && !part.synthetic && !part.ignored)
        .map((part) => part.text)
        .join("\n")
      remember(sessionID, "user", text)
    },
  }
}
