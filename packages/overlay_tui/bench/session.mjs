// Benchmark-only adapter around the original TypeScript/Solid application.
// Keep the application and its native dependencies identical to the baseline.
await import("@opentui/solid/preload");
const { testRender } = await import("@opentui/solid");
const { App } = await import("../src/ui/app.tsx");
const { getTreeSitterClient } = await import("@opentui/core");

export async function start(overlay) {
  const port = { onmessage: null, onerror: null, postMessage() {}, terminate() {} };
  const setup = await testRender(() => App({ args: overlay ? ["overlay", "benchmark"] : [], port, cwd: "benchmark" }), { width: 110, height: 34 });
  const emit = json => port.onmessage?.({ data: JSON.parse(json) });
  emit(JSON.stringify(overlay ? { type: "overlay-ready", model: "benchmark" } : { type: "ready", packages: ["standard"] }));
  return {
    emit,
    render: () => setup.renderOnce(),
    capture: () => setup.captureCharFrame(),
    type: text => setup.mockInput.typeText(text),
    key: name => setup.mockInput.pressKey(name),
    warmParser: async () => { await getTreeSitterClient().initialize(); if (!await getTreeSitterClient().preloadParser("markdown")) throw new Error("Markdown parser unavailable"); },
    drainParser: async () => { await getTreeSitterClient().getPerformance(); await Bun.sleep(0); },
    stop: () => setup.renderer.destroy(),
  };
}
