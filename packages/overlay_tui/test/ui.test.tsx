import { expect, test } from "bun:test";
import { testRender } from "@opentui/solid";
import { App, type RuntimePort } from "../src/ui/app";
import type { RuntimeRequest } from "../src/protocol";
import { RuntimeProcess } from "../src/runtime-process";

test("real terminal input submits source and expands the run effect log", async () => {
  const requests: RuntimeRequest[] = [];
  const port: RuntimePort = { onmessage: null, onerror: null, terminate() {}, postMessage(request) { requests.push(request); } };
  const view = await testRender(() => <App args={[]} port={port} />, { width: 100, height: 32 });
  try {
    await view.renderOnce();
    port.onmessage?.({ data: { type: "ready", packages: ["standard"] } } as MessageEvent);
    await view.mockInput.typeText('perform StandardOut("hello")');
    await view.renderOnce();
    expect(view.captureCharFrame()).toContain('perform StandardOut("hello")');
    view.mockInput.pressEnter();
    await view.renderOnce();
    expect(requests).toContainEqual({ type: "evaluate", id: 1, source: 'perform StandardOut("hello")' });
    port.onmessage?.({ data: { type: "effect", id: 1, effect: { label: "StandardOut", input: '"hello"', output: "{}" } } } as MessageEvent);
    port.onmessage?.({ data: { type: "complete", id: 1, results: [{ text: "{}", error: false }], pending: "", duration: 5 } } as MessageEvent);
    view.mockInput.pressKey("e", { ctrl: true });
    await view.renderOnce();
    expect(view.captureCharFrame()).toContain('StandardOut("hello")');
    expect(view.captureCharFrame()).toContain("↳ {}");
    view.resize(60, 20);
    await view.renderOnce();
    expect(view.captureCharFrame()).toContain("Ready");
  } finally { view.renderer.destroy(); }
});

test("overlay code and effects expand independently after the assistant replies", async () => {
  const port: RuntimePort = { onmessage: null, onerror: null, terminate() {}, postMessage() {} };
  const view = await testRender(() => <App args={["overlay", "config.eyg"]} port={port} />, { width: 100, height: 32 });
  const send = (data: unknown) => port.onmessage?.({ data } as MessageEvent);
  try {
    await view.renderOnce();
    send({ type: "overlay-ready", model: "fixture" });
    send({ type: "tool", id: -1, name: "run", code: 'perform StandardOut("inspect me")' });
    send({ type: "effect", id: -1, effect: { label: "StandardOut", input: '"inspect me"', decision: "pass", output: "{}" } });
    send({ type: "tool-result", id: -1, text: "Done", error: false, duration: 12 });
    send({ type: "assistant", id: -2, text: Array.from({ length: 25 }, (_, index) => `Result line ${index}.`).join("\n\n") });
    await view.renderOnce();
    expect(view.captureCharFrame()).not.toContain("inspect me");
    view.mockInput.pressKey("o", { ctrl: true });
    await view.flush();
    expect(view.captureCharFrame()).toContain('perform StandardOut("inspect me")');
    expect(view.captureCharFrame()).not.toContain("↳ pass");
    view.mockInput.pressKey("e", { ctrl: true });
    await view.flush();
    expect(view.captureCharFrame()).toContain("↳ pass · {}");
    view.mockInput.pressKey("o", { ctrl: true });
    await view.flush();
    expect(view.captureCharFrame()).not.toContain("perform StandardOut");
    expect(view.captureCharFrame()).toContain("↳ pass · {}");
  } finally { view.renderer.destroy(); }
});

test("typing remains responsive while EYG is computing indefinitely in its process", async () => {
  const worker = new RuntimeProcess();
  const ready = new Promise<void>(resolve => worker.addEventListener("message", event => {
    if ((event as MessageEvent).data.type === "ready") resolve();
  }));
  const view = await testRender(() => <App args={[]} port={worker} />, { width: 100, height: 32 });
  try {
    await view.renderOnce();
    await ready;
    await view.mockInput.typeText('!fix((self, x) -> { self(x) })(0)');
    view.mockInput.pressEnter();
    await Bun.sleep(100);
    const started = performance.now();
    await view.mockInput.typeText("next expression");
    await view.renderOnce();
    expect(view.captureCharFrame()).toContain("next expression");
    expect(view.captureCharFrame()).toContain("Running…");
    expect(performance.now() - started).toBeLessThan(250);
  } finally { view.renderer.destroy(); }
}, 10000);

test.each(["", 'let banner = "🌱" ', 'let banner = "緑é" '])("Tab completion replaces the full prefix after %s", async prefix => {
  const requests: RuntimeRequest[] = [];
  const port: RuntimePort = { onmessage: null, onerror: null, terminate() {}, postMessage(request) { requests.push(request); } };
  const view = await testRender(() => <App args={[]} port={port} />, { width: 100, height: 32 });
  try {
    await view.renderOnce();
    port.onmessage?.({ data: { type: "ready", packages: ["standard"] } } as MessageEvent);
    if (prefix) await view.mockInput.pasteBracketedText(prefix);
    await view.mockInput.typeText("let add = @sta");
    await view.flush();
    view.mockInput.pressTab();
    await view.flush();
    await view.mockInput.typeText(".integer.add");
    view.mockInput.pressEnter();
    await view.flush();
    expect(requests).toContainEqual({ type: "evaluate", id: 1, source: prefix + "let add = @standard.integer.add" });
  } finally { view.renderer.destroy(); }
});

test("terminal structural mode edits, undoes, evaluates, and preserves its draft across mode switches", async () => {
  const worker = new RuntimeProcess();
  const next = (type: string) => new Promise<any>(resolve => {
    const listener = (event: Event) => { const message = event as MessageEvent; if (message.data.type === type) { worker.removeEventListener("message", listener); resolve(message.data); } };
    worker.addEventListener("message", listener);
  });
  const ready = next("ready");
  const view = await testRender(() => <App args={[]} port={worker} />, { width: 100, height: 32 });
  async function key(name: string) {
    const update = next("structure"); view.mockInput.pressKey(name === "f2" ? "F2" : name === "right" ? "ARROW_RIGHT" : name === "return" ? "RETURN" : name);
    await Promise.race([update, Bun.sleep(1500).then(() => { throw new Error(`No structural response to ${name}: ${view.captureCharFrame()}`); })]); await view.flush();
  }
  try {
    await view.renderOnce(); await ready;
    await view.mockInput.typeText("!int_add(20, 22)");
    await key("f2");
    expect(view.captureCharFrame()).toContain("Structure");
    await key("right"); await key("right"); await key("n");
    await view.mockInput.typeText("40"); await key("return");
    expect(view.captureCharFrame()).toContain("!int_add(40, 22)");
    await key("z"); expect(view.captureCharFrame()).toContain("!int_add(20, 22)");
    await key("Z"); expect(view.captureCharFrame()).toContain("!int_add(40, 22)");
    view.mockInput.pressKey("F2"); await view.flush();
    expect(view.captureCharFrame()).toContain("!int_add(20, 22)");
    await key("f2"); expect(view.captureCharFrame()).toContain("!int_add(40, 22)");
    const completed = next("complete"); view.mockInput.pressEnter();
    expect((await completed).results).toEqual([{ text: "62", error: false }]);
    await view.flush(); expect(view.captureCharFrame()).toContain("62");
  } finally { view.renderer.destroy(); }
}, 10000);
