// A single driver and event trace for the original TS app and all Gleam apps.
// Run each trial in a fresh Bun process; compile before measuring.
import { cpus } from "node:os";

const [variant = "core", workload = "stream", rowsArg = "100", trial = "1"] = process.argv.slice(2);
const rows = Number(rowsArg);
if (!["typescript", "core", "signals", "lustre"].includes(variant) || !["stream", "typing"].includes(workload) || !Number.isSafeInteger(rows) || rows < 0) throw new Error("Usage: bun bench.mjs typescript|core|signals|lustre stream|typing HISTORY_ROWS TRIAL");
const importStarted = performance.now();
let start;
if (variant === "typescript") {
  ({ start } = await import("../overlay_tui/bench/session.mjs"));
} else {
  const api = await import("./build/dev/javascript/overlay_tui_bench/benchmark.mjs");
  const paths = { core: "overlay_tui_core/core/native_view", signals: "overlay_tui_signals/signals/view", lustre: "overlay_tui_lustre/terminal_lustre/mount" };
  const { mount } = await import(`./build/dev/javascript/${paths[variant]}.mjs`);
  start = async overlay => {
    const session = await api.start(overlay, mount);
    return { emit: json => api.emit(session, json), render: () => api.render(session), capture: () => api.capture(session), type: text => api.type_text(session, text), key: name => api.key(session, name), warmParser: () => api.warm_parser(), drainParser: () => api.drain_parser(), stop: () => api.stop(session) };
  };
}
const importMs = performance.now() - importStarted;
const mountStarted = performance.now();
const session = await start(workload === "stream");
const send = event => session.emit(JSON.stringify(event));
await session.render();
const mountMs = performance.now() - mountStarted;
const rssMounted = process.memoryUsage().rss;
const samples = [];
let historyMs = 0;
let frame;
try {
  if (workload === "stream") await session.warmParser();
  const historyStarted = performance.now();
  for (let index = 0; index < rows; index++) {
    const id = -index - 1;
    send({ type: "tool", id, name: "run", code: `!int_add(${index}, 22)` });
    send({ type: "tool-result", id, text: String(index + 22), error: false, duration: 1 });
  }
  await session.render();
  historyMs = performance.now() - historyStarted;
  if (workload === "stream") {
    await session.type("Render the benchmark response");
    session.key("RETURN");
  }
  // A real event and native frame for each warm-up/sample; no frame-rate timer.
  for (let index = 0; index < 160; index++) {
    const event = JSON.stringify({ type: "assistant", id: -100000, text: `Chunk ${index}. **Measured** text and \`code\`.\n\n` });
    const character = "let value = !int_add(20, 22) "[index % 29];
    const started = performance.now();
    if (workload === "stream") session.emit(event);
    else await session.type(character);
    await session.render();
    const elapsed = performance.now() - started;
    if (index >= 40) samples.push(elapsed);
  }
  frame = session.capture();
  if (workload === "stream" && !frame.includes("Chunk 159")) throw new Error("Streaming frame did not reach the final chunk");
  if (workload === "typing" && !frame.includes("let value")) throw new Error("Input was not rendered");
} finally {
  if (workload === "stream") await session.drainParser();
  await session.stop();
}
const memory = process.memoryUsage();
const sorted = [...samples].sort((a, b) => a - b);
const percentile = p => sorted[Math.ceil(p * sorted.length) - 1];
console.log(JSON.stringify({ variant, workload, history_rows: rows, source_revision: process.env.EYG_TUI_BENCH_REVISION ?? null, opentui: "0.5.14", trial: Number(trial), date: new Date().toISOString(), bun: Bun.version, platform: process.platform, arch: process.arch, cpu: cpus()[0]?.model, columns: 110, lines: 34, warmup: 40, samples: samples.length, import_ms: importMs, mount_ms: mountMs, history_ms: historyMs, mean_ms: samples.reduce((a, b) => a + b, 0) / samples.length, median_ms: percentile(.5), p95_ms: percentile(.95), p99_ms: percentile(.99), rss_mounted_bytes: rssMounted, rss_after_bytes: memory.rss, heap_after_bytes: memory.heapUsed, frame_hash: Bun.hash(frame).toString(), latencies_ms: samples }));
