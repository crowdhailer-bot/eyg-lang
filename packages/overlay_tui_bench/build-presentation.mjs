import { readFile, writeFile } from "node:fs/promises";

const summary = JSON.parse(await readFile(new URL("./results/summary.json", import.meta.url), "utf8"));
const template = await readFile(new URL("./presentation.template.html", import.meta.url), "utf8");
const names = { typescript: "TypeScript / Solid", core: "Gleam / direct core", signals: "Gleam / signals", lustre: "Gleam / Lustre" };
const rows = Object.keys(names).map(variant => {
  const stream = summary.rows.find(row => row.variant === variant && row.workload === "stream" && row.history_rows === 200);
  const typing = summary.rows.find(row => row.variant === variant && row.workload === "typing" && row.history_rows === 200);
  return '<tr' + (variant === "core" ? ' class="chosen"' : '') + '><td>' + names[variant] + '</td><td>' + stream.mean_ms.toFixed(2) + ' / ' + stream.p95_ms.toFixed(2) + '</td><td>' + typing.mean_ms.toFixed(2) + ' / ' + typing.p95_ms.toFixed(2) + '</td><td>' + stream.rss_after_mib.toFixed(1) + '</td></tr>';
}).join("\n");
const table = '<table><thead><tr><th>Frontend</th><th>Streaming mean / p95</th><th>Typing mean / p95</th><th>Streaming RSS (MiB)</th></tr></thead><tbody>' + rows + '</tbody></table>';
const row = (variant, workload) => summary.rows.find(row => row.variant === variant && row.workload === workload && row.history_rows === 200);
const original = row("typescript", "stream"), core = row("core", "stream"), signals = row("signals", "stream");
const overlap = Math.max(core.min_trial_mean_ms, signals.min_trial_mean_ms) <= Math.min(core.max_trial_mean_ms, signals.max_trial_mean_ms);
const replacements = {
  RESULT_TABLE: table,
  BENCHMARK: JSON.stringify(summary).replaceAll("<", "\\u003c"),
  DIRECT_STREAM_COMPARISON: `Direct core: ${core.mean_ms.toFixed(1)} vs ${original.mean_ms.toFixed(1)} ms`,
  STREAM_DESCRIPTION: `About ${Math.round(100 * (1 - core.mean_ms / original.mean_ms))}% lower streaming frame latency than the current original. Streaming RSS is about ${Math.round(core.rss_after_mib)} vs ${Math.round(original.rss_after_mib)} MiB.`,
  TYPING_DESCRIPTION: `Original ${row("typescript", "typing").mean_ms.toFixed(2)} ms; direct core ${row("core", "typing").mean_ms.toFixed(2)} ms. Creating 200 history rows also favors the original: about ${Math.round(original.history_ms)} vs ${Math.round(core.history_ms)} ms in the streaming trials.`,
  SIGNALS_DESCRIPTION: `Signals average ${signals.mean_ms.toFixed(2)} ms versus direct core's ${core.mean_ms.toFixed(2)} ms for streaming. Their trial ranges ${overlap ? "overlap" : "do not overlap"}; this gap alone does not justify a new reactive framework.`,
};
let html = template;
for (const [key, value] of Object.entries(replacements)) html = html.replaceAll(`@@${key}@@`, value);
if (html.includes("@@")) throw new Error("Unexpanded presentation placeholder");
await writeFile(new URL("./presentation.html", import.meta.url), html);
console.log("Built standalone presentation.html from the checked-in benchmark summary.");
