// A pi extension that adds an `eyg` tool.
// Every effect of the agent's EYG program is decided by a policy written in EYG,
// and pi's other tools are effects too, i.e. `perform Read({path: "README.md"})`.
// With `--eyg-only` the model is given only the `eyg` tool. See ../README.md.
import { Agent, type AgentTool, type AgentToolResult } from "@earendil-works/pi-agent-core"
import type { ExtensionAPI, ExtensionContext, ExtensionToolContext } from "@earendil-works/pi-coding-agent"
import { Type } from "typebox"
import { statSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import * as core from "../../opencode_plugin/plugin/core.ts"
import SYNTAX from "../../../guides/syntax.md" with { type: "text" }
import DEFAULT from "../../opencode_plugin/plugin/default.eyg" with { type: "text" }
import { argument, label, result, type } from "./tools.ts"

type Policy = unknown
type Config = unknown
type Callable = { name: string; description: string; parameters: unknown }

const NAME = "eyg"
const TASK_LIFT = "{agent: String, prompt: String, policy: {..gates}}"

const INSTRUCTIONS = `Run an EYG program. Call effects with \`perform Label(lift)\`, every effect is decided by the user's policy.
Effects that are not listed are unavailable. pi's tools are effects, their fields are snake case and fields marked ? can be left out.
The variable \`context\` is in scope and each run has a fresh scope. The final value and StandardOut/StandardError output are the result.
Relative paths are resolved from the working directory. File paths are absolute when a gate sees them.
A policy is a record of gate functions, one field per effect in snake case, \`ReadFile\` is decided by \`read_file\`.
A gate returns \`Pass(lift)\` to perform the effect or \`Mock(lower)\` to return a value instead, \`Pass\` alone allows everything.`

const TASK = `\`Task\` starts a subagent whose only tool is eyg and returns its final answer. Its policy is your policy, or the agent's own policy from the configuration, restricted by the record of gates you give, i.e. \`{read: Pass}\`. Effects without a field are removed.`
const ESCALATE = `\`Escalate\` is the same as \`Task\` but the policy you give replaces yours, the user is asked to approve it.`

export default async function (pi: ExtensionAPI) {
  pi.registerFlag("eyg-only", {
    type: "boolean",
    description: "Give the model only the eyg tool, pi's other tools are EYG effects",
    default: false,
  })

  const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent")
  let cwd = process.cwd()
  let loaded: { key: string; config: Config } | undefined

  async function config(): Promise<Config> {
    const file = [process.env.PI_EYG_CONFIG, join(cwd, ".pi", "eyg.eyg"), join(agentDir, "eyg.eyg")].find(
      (file) => file && statSync(file, { throwIfNoEntry: false })?.isFile(),
    )
    const key = file ? `${file}:${statSync(file).mtimeMs}` : `default:${cwd}`
    if (loaded?.key === key) return loaded.config
    const outcome = file
      ? await core.load(file)
      : await core.load_source(DEFAULT.replace('"PROJECT"', JSON.stringify(cwd)), join(cwd, "eyg"))
    if (!outcome.isOk()) throw new Error(`Failed to load EYG configuration ${file ?? "default"}\n${outcome[0]}`)
    loaded = { key, config: outcome[0] }
    return loaded.config
  }

  const only = () => pi.getFlag("eyg-only") === true || process.env.PI_EYG_ONLY === "1"

  // Effects for pi's tools, the eyg tool itself is never an effect.
  function toolHosts(callable: readonly Callable[], run?: (name: string, args: unknown) => Promise<unknown>) {
    return callable
      .filter((tool) => tool.name !== NAME)
      .map((tool) =>
        core.host(label(tool.name), type(tool.parameters as never), "Any", async (input: unknown) => {
          if (!run) throw new Error("not running")
          return run(tool.name, argument(input ?? {}, tool.parameters as never))
        }),
      )
  }

  // Run a pi tool for a program, through pi's validation, hooks and events.
  async function runTool(ctx: ExtensionToolContext, name: string, args: unknown, signal?: AbortSignal) {
    const outcome = await ctx.executeTool(name, args, { signal })
    const text = outcome.result.content.map((part) => (part.type === "text" ? part.text : `[${part.type}]`)).join("\n")
    if (outcome.isError) throw new Error(text)
    const structured = (outcome.result as { structuredContent?: unknown }).structuredContent
    return structured === undefined ? text : result(structured)
  }

  function describe(policy: Policy, callable: readonly Callable[], cfg: Config) {
    const effects = core.describe(policy, core.toList([...toolHosts(callable), ...subagentHosts()]))
    const agents = core.agent_names(cfg).toArray()
    return [
      INSTRUCTIONS,
      "## Effects available",
      effects || "(none, only pure computation)",
      effects.includes("Task:") ? TASK : "",
      effects.includes("Task:") && agents.length ? `Agents with their own policy: ${agents.join(", ")}.` : "",
      effects.includes("Escalate:") ? ESCALATE : "",
      core.config_readme(cfg) ? `## Context\n${core.config_readme(cfg)}` : "",
      SYNTAX,
    ]
      .filter(Boolean)
      .join("\n\n")
  }

  // Placeholders so that describe() can list Task and Escalate when the policy allows them.
  function subagentHosts(start?: (task: any, raw: unknown, escalate: boolean) => Promise<string>) {
    const handler = (escalate: boolean) => async (task: unknown, raw: unknown) => {
      if (!start) throw new Error("not running")
      return start(task, raw, escalate)
    }
    return [
      core.host("Task", TASK_LIFT, "String", handler(false)),
      core.host("Escalate", TASK_LIFT, "String", handler(true)),
    ]
  }

  // Run a program under a policy. Subagents started by it get their own eyg tool with their policy.
  async function execute(code: string, policy: Policy, ctx: ExtensionToolContext, signal?: AbortSignal) {
    const cfg = await config()
    const start = async (task: { agent: string; prompt: string }, raw: unknown, escalate: boolean) => {
      const requested = core.field(raw, "policy")
      if (!requested.isOk()) throw new Error("a subagent needs a policy field")
      let child
      if (escalate) {
        child = core.replace(requested[0])
        if (!child.isOk()) throw new Error(child[0])
        const fields = core.fields(child[0]).toArray().join(", ")
        const approved =
          ctx.hasUI &&
          (await ctx.ui.confirm(
            "Escalate to a subagent?",
            `Agent: ${task.agent}\nEffects: ${fields || "none"}\n\n${task.prompt}`,
          ))
        if (!approved) throw new Error("the user did not approve the escalation")
      } else {
        const own = core.agent_policy(cfg, String(task.agent))
        child = core.restrict(own.isOk() ? own[0] : policy, requested[0])
        if (!child.isOk()) throw new Error(child[0])
      }
      return subagent(String(task.agent), String(task.prompt), child[0], ctx, signal)
    }
    const hosts = core.toList([
      ...toolHosts(ctx.tools, (name, args) => runTool(ctx, name, args, signal)),
      ...subagentHosts(start),
    ])
    const report = await core.run(code, policy, core.config_context(cfg), ctx.cwd, hosts)
    const effects = [...new Set(core.report_effects(report).toArray() as string[])]
    const ok = core.report_ok(report)
    const text = (ok ? "" : "Error\n") + core.report_text(report)
    return { ok, text, effects }
  }

  // A subagent is an in-process pi-agent-core Agent whose only tool is eyg, under the given policy.
  async function subagent(
    name: string,
    prompt: string,
    policy: Policy,
    ctx: ExtensionToolContext,
    signal?: AbortSignal,
  ): Promise<string> {
    const model = ctx.model
    if (!model) throw new Error("no model selected")
    const cfg = await config()
    const tool: AgentTool = {
      name: NAME,
      label: NAME,
      description: describe(policy, ctx.tools, cfg),
      parameters: Type.Object({ code: Type.String({ description: "EYG source code to run" }) }),
      execute: async (_id, params: { code: string }, toolSignal) => {
        const outcome = await execute(params.code, policy, ctx, toolSignal ?? signal)
        if (!outcome.ok) throw new Error(outcome.text)
        return { content: [{ type: "text", text: outcome.text }], details: { effects: outcome.effects } }
      },
    }
    const agent = new Agent({
      initialState: {
        systemPrompt: `You are the ${name} subagent. Do the task you are given with the eyg tool and answer with the result only.`,
        model,
        tools: [tool],
      },
      streamFn: ctx.modelRegistry.streamSimple.bind(ctx.modelRegistry),
    })
    const abort = () => agent.abort()
    signal?.addEventListener("abort", abort, { once: true })
    try {
      await agent.prompt(prompt)
    } finally {
      signal?.removeEventListener("abort", abort)
    }
    const last = agent.state.messages.findLast((message) => message.role === "assistant")
    if (!last || last.role !== "assistant") return ""
    if (last.stopReason === "error") throw new Error(last.errorMessage ?? "the subagent failed")
    return last.content.flatMap((part) => (part.type === "text" ? [part.text] : [])).join("\n")
  }

  await config().catch(() => undefined)

  pi.on("session_start", async (_event, ctx: ExtensionContext) => {
    cwd = ctx.cwd
    await config()
  })

  pi.registerTool({
    name: NAME,
    label: "EYG",
    description: INSTRUCTIONS,
    promptSnippet: "Run EYG programs, every effect is checked by the user's policy",
    parameters: Type.Object({ code: Type.String({ description: "EYG source code to run" }) }),
    executionMode: "sequential",
    prepareLoadout: (loadout) => {
      if (!loaded) return undefined
      const cfg = loaded.config
      return {
        descriptions: { [NAME]: describe(core.config_policy(cfg), loadout.callable, cfg) },
        hiddenDeclarations: only() ? loadout.declared.map((tool) => tool.name).filter((name) => name !== NAME) : [],
      }
    },
    async execute(_toolCallId, params, signal, _onUpdate, ctx): Promise<AgentToolResult<{ effects: string[] }>> {
      const cfg = await config()
      const outcome = await execute(params.code, core.config_policy(cfg), ctx, signal)
      if (!outcome.ok) throw new Error(outcome.text)
      return { content: [{ type: "text", text: outcome.text }], details: { effects: outcome.effects } }
    },
  })
}

