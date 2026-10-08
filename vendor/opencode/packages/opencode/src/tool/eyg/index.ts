import type { JSONSchema7, JSONSchema7Definition } from "@ai-sdk/provider"
import { statSync } from "fs"
import { homedir } from "os"
import path from "path"
import * as Runtime from "./runtime.js"
import SYNTAX from "./syntax.md" with { type: "text" }
import BUILTINS from "./builtins.md" with { type: "text" }
import DEFAULT from "./default.eyg" with { type: "text" }

export const id = "eyg"

/** A tool that EYG programs call as an effect, i.e. the `read` tool is `perform Read({filePath: "..."})`. */
export type Effect = {
  id: string
  description: string
  schema: JSONSchema7
  // The task tool reports the session it starts, so the session's policy can be set before it runs.
  execute(args: Record<string, unknown>, started: (sessionID: string) => void): Promise<string>
}

export type Session = {
  id: string
  parentID?: string
  directory: string
  agent: string
}

// Policies are EYG closures, they live in memory for as long as the process.
// A session keeps the policy it started with.
const policies = new Map<string, Runtime.Policy>()
let loaded: { key: string; config: Runtime.Config } | undefined

async function config(directory: string) {
  const file = [
    process.env.OPENCODE_EYG_CONFIG,
    path.join(directory, ".opencode", "eyg.eyg"),
    path.join(homedir(), ".config", "opencode", "eyg.eyg"),
  ].find((file) => file && statSync(file, { throwIfNoEntry: false })?.isFile())
  const key = file ? `${file}:${statSync(file).mtimeMs}` : `default:${directory}`
  if (loaded?.key === key) return loaded.config
  const result = file
    ? await Runtime.load(file)
    : await Runtime.load_source(DEFAULT.replace('"PROJECT"', JSON.stringify(directory)), path.join(directory, "eyg"))
  if (!result.isOk()) throw new Error(`Failed to load EYG configuration ${file ?? "default"}\n${result[0]}`)
  policies.clear()
  loaded = { key, config: result[0] as Runtime.Config }
  return loaded.config
}

// The policy for a session is the one it started with, its agent's policy from the configuration,
// or its parent's policy. The top level session uses the configured policy.
async function policyFor(
  cfg: Runtime.Config,
  session: Session,
  parent: (id: string) => Promise<Session | undefined>,
): Promise<Runtime.Policy> {
  const known = policies.get(session.id)
  if (known) return known
  const own = Runtime.agent_policy(cfg, session.agent)
  const above = session.parentID ? await parent(session.parentID) : undefined
  const policy = own.isOk()
    ? (own[0] as Runtime.Policy)
    : above
      ? await policyFor(cfg, above, parent)
      : Runtime.config_policy(cfg)
  policies.set(session.id, policy)
  return policy
}

/** Tool ids become effect labels, `apply_patch` is `ApplyPatch`, and the policy field is the id in snake case. */
export function label(id: string) {
  return id
    .split(/[_\-.]/)
    .filter(Boolean)
    .map((part) => part[0]!.toUpperCase() + part.slice(1))
    .join("")
}

/** The policy field for an effect label, the same rule as the runtime, `ApplyPatch` is `apply_patch`. */
export function field(label: string) {
  return snake(label)
}

// EYG field names are lower case, so tool arguments such as `filePath` are written `file_path` in EYG.
function snake(name: string) {
  return name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()
}

function object(schema: JSONSchema7Definition | undefined) {
  return schema && typeof schema !== "boolean" ? (schema.anyOf?.[0] ?? schema) : undefined
}

function type(definition: JSONSchema7Definition | undefined): string {
  const schema = object(definition)
  if (!schema || typeof schema === "boolean") return "Any"
  if (schema.type === "string") return "String"
  if (schema.type === "integer" || schema.type === "number") return "Integer"
  if (schema.type === "boolean") return "True({}) | False({})"
  if (schema.type === "array") return `List(${type(Array.isArray(schema.items) ? schema.items[0] : schema.items)})`
  if (schema.type === "object" || schema.properties) {
    const required = new Set(schema.required ?? [])
    const fields = Object.entries(schema.properties ?? {}).map(
      ([name, field]) => `${snake(name)}${required.has(name) ? "" : "?"}: ${type(field)}`,
    )
    return `{${fields.join(", ")}}`
  }
  return "Any"
}

// Arguments from EYG have snake case fields and no null, use the field names of the tool's schema.
function argument(value: unknown, definition: JSONSchema7Definition | undefined): unknown {
  const schema = object(definition)
  if (Array.isArray(value)) {
    const items = schema && typeof schema !== "boolean" ? schema.items : undefined
    return value.map((item) => argument(item, Array.isArray(items) ? items[0] : items))
  }
  if (typeof value !== "object" || value === null || value instanceof Uint8Array) return value
  const properties = (schema && typeof schema !== "boolean" ? schema.properties : undefined) ?? {}
  return Object.fromEntries(
    Object.entries(value)
      .filter((entry) => entry[1] !== null && entry[1] !== undefined)
      .map(([key, item]) => {
        const name = Object.keys(properties).find((name) => snake(name) === key) ?? key
        return [name, argument(item, properties[name])]
      }),
  )
}

// Write a JSON value as EYG source.
function source(value: unknown): string {
  if (typeof value === "string") return JSON.stringify(value)
  if (typeof value === "number") return Number.isInteger(value) ? String(value) : JSON.stringify(String(value))
  if (typeof value === "boolean") return value ? "True({})" : "False({})"
  if (Array.isArray(value)) return `[${value.map(source).join(", ")}]`
  if (typeof value === "object" && value !== null)
    return `{${Object.entries(value)
      .filter((entry) => entry[1] !== null && entry[1] !== undefined)
      .map(([key, item]) => `${snake(key)}: ${source(item)}`)
      .join(", ")}}`
  return "{}"
}

/** The program for a direct call to a tool, so that it is checked by the policy like any other effect. */
export function single(id: string, args: Record<string, unknown>) {
  return `match perform ${label(id)}(${source(args)}) {
  Ok(output) -> { output }
  Error(reason) -> { Error(reason) }
}`
}

function hosts(effects: Effect[], cfg: Runtime.Config, policy: Runtime.Policy) {
  return Runtime.toList(
    effects.map((effect) =>
      Runtime.host(label(effect.id), type(effect.schema), "String", async (input, raw) => {
        const args = argument(typeof input === "object" && input !== null ? input : {}, effect.schema) as Record<
          string,
          unknown
        >
        if (effect.id !== "task") return effect.execute(args, () => {})
        // A subagent starts from its agent's configured policy, or this policy,
        // restricted by the policy field when one is given.
        const own = Runtime.agent_policy(cfg, String(args.subagent_type))
        const base = own.isOk() ? (own[0] as Runtime.Policy) : policy
        const requested = Runtime.field(raw, "policy")
        const child = requested.isOk() ? Runtime.restrict(base, requested[0] as Runtime.Value) : undefined
        if (child && !child.isOk()) throw new Error(String(child[0]))
        delete args.policy
        return effect.execute(args, (sessionID) => {
          policies.set(sessionID, child ? (child[0] as Runtime.Policy) : base)
        })
      }),
    ),
  )
}

/** The description of the `eyg` tool for a session, it lists the effects its policy allows. */
export async function describe(input: {
  session: Session
  effects: Effect[]
  parent: (id: string) => Promise<Session | undefined>
}) {
  const cfg = await config(input.session.directory)
  const policy = await policyFor(cfg, input.session, input.parent)
  const available = Runtime.describe(policy, hosts(input.effects, cfg, policy))
  const fields = new Set(Runtime.fields(policy).toArray())
  const tools = input.effects
    .filter((effect) => fields.has(field(label(effect.id))))
    .map((effect) => `### ${label(effect.id)}\n${effect.description.split("\n\n")[0]}`)
  const agents = Runtime.agent_names(cfg).toArray()
  const readme = Runtime.config_readme(cfg)
  return [
    "Run an EYG program. This is your only tool, every action, including opencode's other tools, is an effect performed by an EYG program.",
    "Call an effect with `perform Label(lift)`, every effect is decided by the user's policy, an effect that is not listed is unavailable.",
    'Opencode\'s tools return `Ok(output)` or `Error(reason)`. Their fields are in snake case, i.e. `perform Read({file_path: "README.md"})`, and fields marked `?` are optional and can be left out.',
    "The variable `context` is in scope and each run has a fresh scope. The final value and StandardOut/StandardError output are the result.",
    "Relative paths are resolved from the project directory.",
    "## Effects available",
    available || "(none, only pure computation)",
    fields.has("task")
      ? "`Task` takes an optional `policy` field, a record of gate functions, i.e. `{read: Pass, grep: Pass}`. The subagent's policy is yours, or its agent's own policy, restricted by it. Effects without a field are removed. A gate returns `Pass(lift)` to allow an effect or `Mock(lower)` to return a value instead. Fields are effect names in snake case."
      : "",
    fields.has("task") && agents.length ? `Agents with their own policy: ${agents.join(", ")}` : "",
    tools.length ? `## Opencode tools\n${tools.join("\n\n")}` : "",
    readme ? `## Context\n${readme}` : "",
    SYNTAX,
    BUILTINS,
  ]
    .filter(Boolean)
    .join("\n\n")
}

export async function execute(input: {
  code: string
  session: Session
  effects: Effect[]
  parent: (id: string) => Promise<Session | undefined>
}) {
  const cfg = await config(input.session.directory)
  const policy = await policyFor(cfg, input.session, input.parent)
  const report = await Runtime.run(
    input.code,
    policy,
    Runtime.config_context(cfg),
    input.session.directory,
    hosts(input.effects, cfg, policy),
  )
  const effects = [...new Set(Runtime.report_effects(report).toArray())]
  const ok = Runtime.report_ok(report)
  return {
    title: effects.length ? effects.join(", ") : "pure",
    output: (ok ? "" : "Error\n") + Runtime.report_text(report),
    metadata: { ok, effects },
  }
}

export * as Eyg from "."
