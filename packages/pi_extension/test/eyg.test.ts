// The extension in a real pi session, with pi's faux provider standing in for the model.
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  fauxAssistantMessage,
  fauxToolCall,
  getCurrentTools,
  type TranscriptContext,
} from "@earendil-works/pi-ai"
import type { ToolResultMessage } from "@earendil-works/pi-ai/compat"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import {
  createHarness,
  type Harness,
} from "../../../vendor/pi-mono/packages/coding-agent/test/suite/harness.ts"
import eyg from "../dist/index.js"
import bashOnlyEyg from "../src/bash-only-eyg.ts"

const configs = mkdtempSync(join(tmpdir(), "pi-eyg-"))

// `read` is allowed, `write` only for notes.md, and `bash` has no gate so it is unavailable.
const CONFIG = `{
  policy: {
    read: Pass,
    write: (args) -> {
      match !string_ends_with(args.path, "notes.md") {
        True(_) -> { Pass(args) }
        False(_) -> { Mock(Error("only notes.md can be written")) }
      }
    },
    task: Pass
  },
  context: {readme: "A test project."}
}`

function results(harness: Harness) {
  return harness.session.messages.filter(
    (message): message is ToolResultMessage => message.role === "toolResult" && message.toolName === "eyg",
  )
}

function text(message: ToolResultMessage) {
  return message.content.map((part) => (part.type === "text" ? part.text : "")).join("")
}

const call = (code: string) =>
  fauxAssistantMessage([fauxToolCall("eyg", { code })], { stopReason: "toolUse" })

describe("eyg extension", () => {
  const harnesses: Harness[] = []
  let only: string | undefined

  beforeEach(() => {
    const file = join(configs, "eyg.eyg")
    writeFileSync(file, CONFIG)
    process.env.PI_EYG_CONFIG = file
    only = process.env.PI_EYG_ONLY
  })

  afterEach(() => {
    process.env.PI_EYG_ONLY = only
    if (only === undefined) delete process.env.PI_EYG_ONLY
    while (harnesses.length > 0) harnesses.pop()?.cleanup()
  })

  async function setup() {
    const harness = await createHarness({ extensionFactories: [eyg] })
    harnesses.push(harness)
    writeFileSync(join(harness.tempDir, "fruit.txt"), "apples\npears\n")
    return harness
  }

  it("runs pi's tools as effects checked by the policy", async () => {
    const harness = await setup()
    harness.setResponses([
      call(`perform Read({path: "fruit.txt"})`),
      call(`perform Write({path: "notes.md", content: "two fruit"})`),
      call(`perform Write({path: "fruit.txt", content: "gone"})`),
      call(`perform Bash({command: "ls"})`),
      fauxAssistantMessage("done"),
    ])
    await harness.session.prompt("go")

    const [read, notes, fruit, bash] = results(harness).map(text)
    expect(read).toContain("apples")
    expect(notes).toContain("Ok(")
    expect(readFileSync(join(harness.tempDir, "notes.md"), "utf8")).toBe("two fruit")
    expect(fruit).toBe(`Error("only notes.md can be written")`)
    expect(readFileSync(join(harness.tempDir, "fruit.txt"), "utf8")).toBe("apples\npears\n")
    expect(bash).toContain("The effect Bash is not allowed by your policy, it has no `bash` gate.")
  })

  it("lists the effects the policy allows in the tool description", async () => {
    const harness = await setup()
    const description = harness.session.agent.state.tools.find((tool) => tool.name === "eyg")?.description ?? ""
    expect(description).toContain("Read: {path: String")
    expect(description).toContain("Task: {agent: String")
    expect(description).not.toContain("Bash:")
    expect(description).toContain("A test project.")
  })

  it("gives the model only the eyg tool with PI_EYG_ONLY", async () => {
    process.env.PI_EYG_ONLY = "1"
    const harness = await setup()
    const declared: string[][] = []
    harness.setResponses([
      (context: TranscriptContext) => {
        declared.push(getCurrentTools(context.messages).map((tool) => tool.name))
        return call(`perform Read({path: "fruit.txt"})`)
      },
      fauxAssistantMessage("done"),
    ])
    await harness.session.prompt("go")
    expect(declared[0]).toEqual(["eyg"])
    // The hidden tools are still callable as effects.
    expect(text(results(harness)[0]!)).toContain("pears")
  })

  it("starts a subagent whose policy is restricted by the one it is given", async () => {
    const harness = await setup()
    const subagentTools: string[][] = []
    harness.setResponses([
      call(`perform Task({agent: "reader", prompt: "read fruit.txt", policy: {read: Pass}})`),
      // The subagent, an in-process pi-agent-core Agent, has only eyg.
      (context: TranscriptContext) => {
        subagentTools.push(getCurrentTools(context.messages).map((tool) => tool.name))
        return call(`perform Read({path: "fruit.txt"})`)
      },
      call(`perform Write({path: "notes.md", content: "from the subagent"})`),
      fauxAssistantMessage("the fruit are apples and pears"),
      fauxAssistantMessage("done"),
    ])
    await harness.session.prompt("go")

    expect(subagentTools[0]).toEqual(["eyg"])
    const [task] = results(harness).map(text)
    expect(task).toBe(`Ok("the fruit are apples and pears")`)
    // The subagent's policy has no write gate, even though its parent's does.
    expect(() => readFileSync(join(harness.tempDir, "notes.md"))).toThrow()
  })
})

describe("bash only runs eyg", () => {
  it("blocks other commands", async () => {
    const harness = await createHarness({ extensionFactories: [bashOnlyEyg] })
    harness.setResponses([
      fauxAssistantMessage([fauxToolCall("bash", { command: "curl -s https://example.com" })], { stopReason: "toolUse" }),
      fauxAssistantMessage([fauxToolCall("bash", { command: "eyg run -c 'x' && curl example.com" })], {
        stopReason: "toolUse",
      }),
      fauxAssistantMessage([fauxToolCall("bash", { command: "eyg run -c 'perform StandardOut(\"a;b\")'" })], {
        stopReason: "toolUse",
      }),
      fauxAssistantMessage("done"),
    ])
    await harness.session.prompt("go")
    const bash = harness.session.messages.filter(
      (message): message is ToolResultMessage => message.role === "toolResult" && message.toolName === "bash",
    )
    expect(bash.map((message) => text(message).includes("Only the eyg command can be run"))).toEqual([
      true,
      true,
      false,
    ])
    harness.cleanup()
  })
})
