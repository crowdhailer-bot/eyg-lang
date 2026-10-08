import { expect } from "bun:test"
import { mkdtempSync, writeFileSync } from "fs"
import { tmpdir } from "os"
import path from "path"
import { ModelV2 } from "@opencode-ai/core/model"
import { ProviderV2 } from "@opencode-ai/core/provider"
import { SessionV1 } from "@opencode-ai/core/v1/session"
import { Agent } from "@/agent/agent"
import { MCP } from "@/mcp"
import { Permission } from "@/permission"
import { Provider } from "@/provider/provider"
import { Session } from "@/session/session"
import { MessageID, SessionID } from "@/session/schema"
import { SessionProcessor } from "@/session/processor"
import { SessionTools } from "@/session/tools"
import { Tool } from "@/tool/tool"
import { ToolRegistry } from "@/tool/registry"
import { Truncate } from "@/tool/truncate"
import { Plugin } from "@/plugin"
import { RuntimeFlags } from "@/effect/runtime-flags"
import { Effect, Layer, Schema } from "effect"
import { testEffect } from "../lib/effect"

const directory = mkdtempSync(path.join(tmpdir(), "opencode-eyg-"))
// The `timing` tool is mocked, `shout` and `task` are allowed and `secret` has no gate so it is unavailable.
writeFileSync(
  path.join(directory, "eyg.eyg"),
  `{
  policy: {
    shout: Pass,
    timing: (_) -> { Mock(Ok("mocked")) },
    task: Pass
  }
}`,
)
process.env.OPENCODE_EYG_CONFIG = path.join(directory, "eyg.eyg")

const agent: Agent.Info = {
  name: "build",
  mode: "primary",
  options: {},
  permission: [{ permission: "*", pattern: "*", action: "allow" }],
}

const model = {
  providerID: ProviderV2.ID.make("test"),
  api: { id: "test-model" },
} as Provider.Model

const tool = (id: string, execute: Tool.Def["execute"]): Tool.Def => ({
  id,
  description: `the ${id} tool`,
  parameters: Schema.Struct({ textValue: Schema.optional(Schema.String) }),
  jsonSchema: { type: "object", properties: { textValue: { type: "string" } } },
  execute,
})

const registry = ToolRegistry.Service.of({
  ids: () => Effect.succeed(["shout", "timing", "secret", "task"]),
  all: () => Effect.succeed([]),
  named: () => Effect.die("unused"),
  tools: () =>
    Effect.succeed([
      tool("shout", (args) =>
        Effect.succeed({ title: "shout", metadata: {}, output: String(args.textValue).toUpperCase() }),
      ),
      tool("timing", () => Effect.succeed({ title: "timing", metadata: {}, output: "performed" })),
      tool("secret", () => Effect.succeed({ title: "secret", metadata: {}, output: "leaked" })),
      // The task tool reports the session it starts, as opencode's does.
      tool("task", (_args, ctx) =>
        ctx
          .metadata({ metadata: { sessionId: "ses_child" } })
          .pipe(Effect.as({ title: "task", metadata: {}, output: "started" })),
      ),
    ]),
})

const layer = (mode: "only" | "gate") =>
  Layer.mergeAll(
    Layer.succeed(
      Plugin.Service,
      Plugin.Service.of({
        init: () => Effect.void,
        list: () => Effect.succeed([]),
        trigger: (_name, _input, output) => Effect.succeed(output),
      } satisfies Plugin.Interface),
    ),
    Layer.succeed(
      Permission.Service,
      Permission.Service.of({
        ask: () => Effect.void,
        reply: () => Effect.void,
        list: () => Effect.succeed([]),
      } satisfies Permission.Interface),
    ),
    Layer.succeed(
      MCP.Service,
      MCP.Service.of({
        tools: () => Effect.succeed({}),
        clients: () => Effect.succeed({}),
      } as Partial<MCP.Interface> as MCP.Interface),
    ),
    Layer.succeed(
      Truncate.Service,
      Truncate.Service.of({
        cleanup: () => Effect.void,
        write: () => Effect.succeed("output.txt"),
        output: (text: string) => Effect.succeed({ content: text, truncated: false }),
        limits: () => Effect.succeed({ maxLines: 2000, maxBytes: 50 * 1024 }),
      } satisfies Truncate.Interface),
    ),
    Layer.succeed(
      Session.Service,
      Session.Service.of({ get: () => Effect.die("no parent") } as Partial<Session.Interface> as Session.Interface),
    ),
    RuntimeFlags.layer({ eyg: mode }),
    Layer.succeed(ToolRegistry.Service, registry),
  )

const processor = {
  message: {
    id: MessageID.ascending(),
    sessionID: SessionID.make("ses_eyg"),
    role: "assistant",
    parentID: MessageID.ascending(),
    agent: "build",
    mode: "build",
    path: { cwd: directory, root: directory },
    cost: 0,
    tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
    modelID: ModelV2.ID.make("test-model"),
    providerID: ProviderV2.ID.make("test"),
    time: { created: 1 },
  } satisfies SessionV1.Assistant,
  updateToolCall: () => Effect.void,
  completeToolCall: () => Effect.void,
} as unknown as Pick<SessionProcessor.Handle, "message" | "updateToolCall" | "completeToolCall">

const resolveFor = (session: { id: string; parentID?: string }) =>
  SessionTools.resolve({
    agent,
    model,
    session: {
      id: SessionID.make(session.id),
      parentID: session.parentID ? SessionID.make(session.parentID) : undefined,
      permission: [],
      directory,
    } as unknown as Session.Info,
    processor,
    bypassAgentCheck: false,
    messages: [],
    promptOps: {} as never,
  })
const resolve = resolveFor({ id: "ses_eyg" })

const options = { toolCallId: "call-eyg", abortSignal: new AbortController().signal, messages: [] }

testEffect(layer("only")).effect("eyg is the only tool and other tools are effects", () =>
  Effect.gen(function* () {
    const tools = yield* resolve
    expect(Object.keys(tools)).toEqual(["eyg"])
    const description = tools.eyg.description ?? ""
    expect(description).toContain("Shout: {text_value?: String}")
    expect(description).not.toContain("Secret:")

    const run = (code: string) => Effect.promise(() => tools.eyg.execute!({ code }, options))
    expect((yield* run(`perform Shout({text_value: "hi"})`)).output).toBe(`Ok("HI")`)
    expect((yield* run(`perform Timing({})`)).output).toBe(`Ok("mocked")`)
    expect((yield* run(`perform Secret({})`)).output).toContain(
      "The effect Secret is not allowed by your policy, it has no `secret` gate.",
    )
  }),
)

testEffect(layer("gate")).effect("calls to other tools are checked by the policy", () =>
  Effect.gen(function* () {
    const tools = yield* resolve
    expect(Object.keys(tools).toSorted()).toEqual(["eyg", "secret", "shout", "task", "timing"])
    const call = (id: string, args: Record<string, unknown>) => Effect.promise(() => tools[id]!.execute!(args, options))
    expect((yield* call("shout", { textValue: "hi" })).output).toBe("HI")
    expect((yield* call("timing", {})).output).toBe("mocked")
    expect((yield* call("secret", {})).output).toContain("not allowed by your policy")
  }),
)

testEffect(layer("only")).effect("a subagent started by Task has the policy it was given", () =>
  Effect.gen(function* () {
    const tools = yield* resolve
    const started = yield* Effect.promise(() =>
      tools.eyg.execute!(
        {
          code: `perform Task({description: "shout", prompt: "shout", subagent_type: "general", policy: {shout: Pass}})`,
        },
        options,
      ),
    )
    expect(started.output).toBe(`Ok("started")`)
    const child = yield* resolveFor({ id: "ses_child", parentID: "ses_eyg" })
    const description = child.eyg.description ?? ""
    expect(description).toContain("Shout:")
    expect(description).not.toContain("Timing:")
    expect(description).not.toContain("Task:")
  }),
)
