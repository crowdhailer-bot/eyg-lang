// An opencode plugin that adds an `eyg` tool.
// Every effect performed by the agent's EYG program is decided by a policy written in EYG.
// See ../README.md for configuration.
import type { Plugin } from "@opencode-ai/plugin"
import { toList } from "../build/dev/javascript/opencode_plugin/gleam.mjs"
import * as core from "../build/dev/javascript/opencode_plugin/opencode_plugin.mjs"
import { homedir } from "node:os"
import { join } from "node:path"
import { statSync } from "node:fs"
import SYNTAX from "../../../guides/syntax.md" with { type: "text" }
import BUILTINS from "../../../guides/builtins_reference.md" with { type: "text" }
import DEFAULT from "./default.eyg" with { type: "text" }

type Policy = unknown
type Config = unknown
type Session = { sessionID: string; agent: string; directory: string; ask: (input: any) => Promise<void> }

const DESCRIPTION = `Run an EYG program. EYG is the only way to act on the system, use it to read, search and edit files, fetch from the web and start subagents.
Effects are called with \`perform Label(lift)\` and every effect is checked by the user's policy, effects not listed are unavailable.
The variable \`context\` is in scope, each run has a fresh scope.
Returned values and StandardOut/StandardError output are included in the result.
Relative paths are resolved from the project directory.`

const TASK_LIFT = "{agent: String, prompt: String, policy: {..gates}}"

export const EygPlugin: Plugin = async (input) => {
  const candidates = [
    process.env.OPENCODE_EYG_CONFIG,
    join(input.directory, ".opencode", "eyg.eyg"),
    join(homedir(), ".config", "opencode", "eyg.eyg"),
  ].filter((path): path is string => !!path)

  let loaded: { path: string; mtime: number; config: Config } | undefined
  let failure: string | undefined
  // Policies for sessions, a session started with the Task effect keeps the policy it was given.
  const sessions = new Map<string, Policy>()

  async function config(): Promise<Config | undefined> {
    const path = candidates.find((path) => statSync(path, { throwIfNoEntry: false })?.isFile())
    const mtime = path ? statSync(path).mtimeMs : 0
    if (loaded && loaded.path === (path ?? "default") && loaded.mtime === mtime) return loaded.config
    const result = path
      ? await core.load(path)
      : await core.load_source(DEFAULT.replace('"PROJECT"', JSON.stringify(input.directory)), join(input.directory, "eyg"))
    if (!result.isOk()) {
      failure = `Failed to load ${path ?? "the default policy"}\n${result[0]}`
      return undefined
    }
    loaded = { path: path ?? "default", mtime, config: result[0] }
    failure = undefined
    sessions.clear()
    return loaded.config
  }

  // The policy for a session is the one it was started with, the one configured for its agent,
  // or the policy of its parent session. The top level session uses the configured policy.
  async function policyFor(cfg: Config, sessionID: string, agent?: string): Promise<Policy> {
    const known = sessions.get(sessionID)
    if (known) return known
    const configured = agent ? core.agent_policy(cfg, agent) : undefined
    let policy: Policy
    if (configured && configured.isOk()) policy = configured[0]
    else {
      const session = await input.client.session.get({ path: { id: sessionID } }).catch(() => undefined)
      const parentID = session?.data?.parentID
      policy = parentID ? await policyFor(cfg, parentID) : core.config_policy(cfg)
    }
    sessions.set(sessionID, policy)
    return policy
  }

  async function subagent(session: Session, task: any, policy: Policy) {
    const child = await input.client.session.create({
      body: { parentID: session.sessionID, title: `${task.agent} (eyg): ${String(task.prompt).split("\n")[0].slice(0, 60)}` },
    })
    if (!child.data) throw new Error("failed to create a session for the subagent")
    sessions.set(child.data.id, policy)
    const reply = await input.client.session.prompt({
      path: { id: child.data.id },
      body: { agent: task.agent, parts: [{ type: "text", text: String(task.prompt) }] },
    })
    const parts = reply.data?.parts ?? []
    const text = parts.filter((part: any) => part.type === "text").map((part: any) => part.text)
    return text.at(-1) ?? ""
  }

  function hosts(session: Session, policy: Policy, cfg?: Config) {
    return toList([
      core.host("Task", TASK_LIFT, "String", async (task: any, raw: unknown) => {
        const requested = core.field(raw, "policy")
        if (!requested.isOk()) throw new Error("Task needs a policy field")
        // A policy the user configured for the agent is the starting point, otherwise the caller's policy.
        const configured = cfg ? core.agent_policy(cfg, String(task.agent)) : undefined
        const base = configured && configured.isOk() ? configured[0] : policy
        const restricted = core.restrict(base, requested[0])
        if (!restricted.isOk()) throw new Error(restricted[0])
        return subagent(session, task, restricted[0])
      }),
      core.host("Escalate", TASK_LIFT, "String", async (task: any, raw: unknown) => {
        const requested = core.field(raw, "policy")
        if (!requested.isOk()) throw new Error("Escalate needs a policy field")
        const replaced = core.replace(requested[0])
        if (!replaced.isOk()) throw new Error(replaced[0])
        await session.ask({
          permission: "eyg_escalate",
          patterns: [String(task.agent)],
          always: [],
          metadata: { agent: task.agent, prompt: task.prompt, effects: core.fields(replaced[0]).toArray() },
        })
        return subagent(session, task, replaced[0])
      }),
    ])
  }

  function describe(policy: Policy) {
    return core.describe(policy, hosts({} as Session, policy))
  }

  return {
    tool: {
      eyg: {
        description: DESCRIPTION,
        args: {
          code: { type: "string", description: "EYG source code to run" },
        },
        async execute(args: { code: string }, ctx) {
          const cfg = await config()
          if (!cfg) return { title: "no policy", output: failure ?? "No EYG configuration", metadata: {} }
          const policy = await policyFor(cfg, ctx.sessionID, ctx.agent)
          const session = { ...ctx, directory: ctx.directory ?? input.directory }
          const report = await core.run(args.code, policy, core.config_context(cfg), session.directory, hosts(session, policy, cfg))
          const effects = [...new Set(core.report_effects(report).toArray())]
          return {
            title: effects.length ? effects.join(", ") : "pure",
            output: (report.ok ? "" : "Error\n") + core.report_text(report),
            metadata: { ok: report.ok, effects },
          }
        },
      },
    },
    "chat.message": async (message) => {
      const cfg = await config()
      if (cfg && message.agent) await policyFor(cfg, message.sessionID, message.agent)
    },
    "experimental.chat.system.transform": async (request, output) => {
      const cfg = await config()
      if (!cfg) return
      const policy = request.sessionID ? await policyFor(cfg, request.sessionID) : core.config_policy(cfg)
      const effects = describe(policy)
      const readme = core.config_readme(cfg)
      output.system.push(
        [
          "# EYG",
          "Use the `eyg` tool to act on the system, write EYG programs and do not guess syntax, follow the guides below.",
          "A policy is a record of gate functions, one field per effect named in snake case, `ReadFile` is decided by `read_file`. A gate returns `Pass(lift)` to perform the effect, possibly with a changed lift, or `Mock(lower)` to return a value without performing it, `Pass` alone is a gate that allows everything. File paths are absolute when a gate sees them, relative paths are resolved from the project directory. DecodeJSON, EYGParse, Flip, Hash, Random, StandardOut and StandardError are always available unless a gate is given.",
          "The effects allowed by your policy are listed here, any other effect is unavailable:",
          effects || "(none, only pure computation)",
          effects.includes("Task:")
            ? "`Task` starts a subagent and returns its final answer. The subagent's policy is your policy, or the agent's own policy if listed below, further restricted by the record of gates you give, i.e. `{read_file: Pass}`. Effects without a field in that record are removed."
            : "",
          effects.includes("Task:") && core.agent_names(cfg).toArray().length
            ? "Agents with their own policy:\n" +
              core
                .agent_names(cfg)
                .toArray()
                .map((name: string) => {
                  const own = core.agent_policy(cfg, name)
                  return `- ${name}: ${own.isOk() ? describe(own[0]).split("\n").map((line: string) => line.split(":")[0]).join(", ") : ""}`
                })
                .join("\n")
            : "",
          effects.includes("Escalate:")
            ? "`Escalate` is the same as `Task` but the policy given replaces yours, the user is asked to approve it."
            : "",
          readme ? `## Context\n${readme}` : "",
          SYNTAX,
          BUILTINS,
        ].join("\n\n"),
      )
    },
  }
}
