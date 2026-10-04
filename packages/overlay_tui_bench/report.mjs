import { readdir, readFile, writeFile } from "node:fs/promises";

const directory = new URL("./results/", import.meta.url);
const files = (await readdir(directory)).filter(file => /^(typescript|core|signals|lustre)-(stream|typing)-\d+-\d+\.json$/.test(file)).sort();
const trials = await Promise.all(files.map(async file => JSON.parse(await readFile(new URL(file, directory), "utf8"))));
if (trials.length !== 80) throw new Error(`Expected 80 trials, found ${trials.length}`);
if (new Set(trials.map(row => row.source_revision)).size !== 1) throw new Error("Mixed source revisions");
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const groups = [];
for (const workload of ["stream", "typing"]) for (const history_rows of [20, 200]) for (const variant of ["typescript", "core", "signals", "lustre"]) {
  const selected = trials.filter(row => row.workload === workload && row.history_rows === history_rows && row.variant === variant);
  if (selected.length !== 5 || new Set(selected.map(row => row.trial)).size !== 5) throw new Error("Incomplete group");
  groups.push({ workload, history_rows, variant, trials: selected.length, samples_per_trial: 120,
    mean_ms: median(selected.map(row => row.mean_ms)),
    p95_ms: median(selected.map(row => row.p95_ms)),
    min_trial_mean_ms: Math.min(...selected.map(row => row.mean_ms)),
    max_trial_mean_ms: Math.max(...selected.map(row => row.mean_ms)),
    import_ms: median(selected.map(row => row.import_ms)),
    mount_ms: median(selected.map(row => row.mount_ms)),
    history_ms: median(selected.map(row => row.history_ms)),
    rss_mounted_mib: median(selected.map(row => row.rss_mounted_bytes / 1048576)),
    rss_after_mib: median(selected.map(row => row.rss_after_bytes / 1048576)),
    heap_after_mib: median(selected.map(row => row.heap_after_bytes / 1048576)),
    frames: [...new Set(selected.map(row => row.frame_hash))],
  });
}
const logs = [];
for (const file of (await readdir(directory)).filter(file => file.endsWith(".log"))) {
  const text = await readFile(new URL(file, directory), "utf8");
  if (text) logs.push({ file, bytes: Buffer.byteLength(text), preview: text.slice(0, 250) });
}
const summary = { recorded_at: new Date().toISOString(), source_revision: trials[0].source_revision, opentui: trials[0].opentui, memory_sampling: "After parser draining and renderer teardown, without forced GC", cpu: trials[0].cpu, bun: trials[0].bun, platform: trials[0].platform, architecture: trials[0].arch, aggregation: "Median of five trial means; p95 is median of five trial p95s. Ranges describe trial means, not confidence intervals.", rows: groups, logs };
await writeFile(new URL("summary.json", directory), JSON.stringify(summary, null, 2) + "\n");
console.table(groups.map(row => ({ workload: row.workload, rows: row.history_rows, frontend: row.variant, mean_ms: row.mean_ms.toFixed(2), p95_ms: row.p95_ms.toFixed(2), history_ms: row.history_ms.toFixed(1), rss_mib: row.rss_after_mib.toFixed(1) })));
console.log(`${trials.length} trials; ${logs.length} nonempty stderr logs`);
