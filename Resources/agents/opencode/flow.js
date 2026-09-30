// Flow loads this plugin into each OpenCode it starts, through
// OPENCODE_CONFIG_CONTENT, so nothing is written to the user's configuration.
// It reports the session's progress to Flow with `flw event`.
import { spawn } from "node:child_process"

const detailLimit = 200

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
  const busy = new Set()
  const live = new Set()
  // The tool each open permission request holds up, by request id.
  const asking = new Map()
  // Flow orders events by when `flw` sends them, so each waits for the one before.
  let sent = Promise.resolve()

  function send(kind, sessionID, detail) {
    if (!sessionID || children.has(sessionID)) return
    live.add(sessionID)
    const args = ["event", kind, "--agent", "opencode", "--session", sessionID]
    if (detail) args.push("--detail", detail)
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
        case "session.idle":
          busy.delete(sessionID)
          send("turnEnded", sessionID, lastText.get(sessionID))
          lastText.delete(sessionID)
          break
        case "permission.asked":
          asking.set(properties.id, properties.permission)
          send("needsInput", sessionID, "permission")
          break
        case "question.asked":
          send("needsInput", sessionID, "question")
          break
        // The session stays busy while it waits, so no busy status follows
        // the answer. A rejection that ends the turn is followed by session.idle.
        case "permission.replied":
          send("working", sessionID, asking.get(properties.requestID))
          asking.delete(properties.requestID)
          break
        case "question.replied":
        case "question.rejected":
          send("working", sessionID)
          break
        case "session.error": {
          const error = properties.error
          send("attention", sessionID, summary(String(error?.data?.message ?? error?.name ?? "error")))
          break
        }
        case "session.deleted":
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
      if (text?.trim()) lastText.set(sessionID, summary(text))
    },
  }
}
