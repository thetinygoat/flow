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
  // A session asks for several things at once when tools run in parallel, and
  // waits until all are answered. By session, each open request's id and the
  // tool it holds up.
  const pending = new Map()
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
          pending.delete(sessionID)
          send("turnEnded", sessionID, lastText.get(sessionID))
          lastText.delete(sessionID)
          break
        case "permission.asked":
        case "question.asked": {
          const permission = event.type === "permission.asked"
          if (!pending.has(sessionID)) pending.set(sessionID, new Map())
          pending.get(sessionID).set(properties.id, permission ? properties.permission : undefined)
          send("needsInput", sessionID, permission ? "permission" : "question")
          break
        }
        // The session stays busy while it waits, so no busy status follows
        // the answer. A rejection that ends the turn is followed by session.idle.
        case "permission.replied":
        case "question.replied":
        case "question.rejected": {
          const requests = pending.get(sessionID)
          const tool = requests?.get(properties.requestID)
          requests?.delete(properties.requestID)
          if (requests?.size) break
          pending.delete(sessionID)
          send("working", sessionID, tool)
          break
        }
        case "session.error": {
          const error = properties.error
          send("attention", sessionID, summary(String(error?.data?.message ?? error?.name ?? "error")))
          break
        }
        case "session.deleted":
          send("sessionEnded", sessionID)
          live.delete(sessionID)
          children.delete(sessionID)
          pending.delete(sessionID)
          break
      }
    },
    "tool.execute.before": async ({ tool, sessionID }) => {
      if (!pending.has(sessionID)) send("working", sessionID, tool)
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
