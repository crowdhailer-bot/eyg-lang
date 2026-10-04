import { expect, test } from "bun:test";
import { OverlayRuntime } from "../src/overlay-runtime";
import { RuntimeProcess } from "../src/runtime-process";
import type { RuntimeEvent } from "../src/protocol";

test("overlay streams a real provider response, runs tools through policy, and records effects", async () => {
  const requests: any[] = [];
  const code = 'let _ = perform StandardOut("hello") perform Now({})';
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch(request) {
    requests.push(await request.json());
    const message = requests.length === 1
      ? { content: "I will run that now.", tool_calls: [{ function: { name: "run", arguments: { code } } }] }
      : { content: "The clock returned 123." };
    return new Response(JSON.stringify({ message, done: true }) + "\n", { headers: { "content-type": "application/x-ndjson" } });
  } });
  try {
    const events: RuntimeEvent[] = [];
    const runtime = new OverlayRuntime(event => events.push(event), async () => "");
    await runtime.initialize(["overlay", "-c", `{
      llm: { provider: Ollama({origin: "${server.url.origin}", api_key: None({})}), model: "fixture" },
      policy: { standard_out: (x) -> { Pass(!string_uppercase(x)) }, now: (_) -> { Mock(123) } },
      context: {}
    }`]);
    await runtime.evaluate(1, "Say hello and read the clock.");
    expect(events).toContainEqual({ type: "overlay-ready", model: "fixture" });
    expect(events.find(event => event.type === "tool")?.code).toBe(code);
    const effects = events.filter(event => event.type === "effect").map(event => event.effect);
    expect(effects).toEqual([
      { label: "StandardOut", input: '"HELLO"', decision: "pass", output: "{}" },
      { label: "Now", input: "{}", decision: "mock", output: "123" },
    ]);
    expect(events.filter(event => event.type === "assistant").map(event => event.text).join("")).toContain("The clock returned 123.");
    expect(requests.length).toBe(2);
    expect(requests[1].messages.some((message: any) => message.role === "tool" && message.content.includes("123"))).toBe(true);
  } finally { server.stop(true); }
});

test("overlay subprocess exchanges permission prompts and logs denied actions over IPC", async () => {
  let calls = 0;
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch() {
    const message = ++calls === 1
      ? { content: "", tool_calls: [{ function: { name: "run", arguments: { code: "perform Now({})" } } }] }
      : { content: "Access denied." };
    return new Response(JSON.stringify({ message, done: true }) + "\n");
  } });
  const runtime = new RuntimeProcess();
  try {
    const events: RuntimeEvent[] = [];
    const prompts: string[] = [];
    let ready!: () => void;
    let complete!: () => void;
    const initialized = new Promise<void>(resolve => { ready = resolve; });
    const finished = new Promise<void>(resolve => { complete = resolve; });
    runtime.onmessage = ({ data: event }) => {
      events.push(event);
      if (event.type === "overlay-ready") ready();
      if (event.type === "complete") complete();
      if (event.type === "prompt") { prompts.push(event.text); runtime.postMessage({ type: "answer", text: "n" }); }
    };
    runtime.postMessage({ type: "initialize", args: ["overlay", "-c", `{
      llm: {provider: Ollama({origin: "${server.url.origin}", api_key: None({})}), model: "fixture"},
      policy: {now: (_) -> { Ask({question: "Read the clock?", denied: 0}) }}, context: {}
    }`] });
    await initialized;
    runtime.postMessage({ type: "evaluate", id: 1, source: "What time is it?" });
    await finished;
    expect(prompts[0]).toContain("Read the clock?");
    expect(events.filter(event => event.type === "effect")[0]?.effect).toEqual({ label: "Now", input: "{}", decision: "mock", output: "0" });
  } finally { await runtime.terminate(); server.stop(true); }
});
