---
name: Comparing terminal frontends
description: Measure real native frames with a Gleam runner and keep historical comparisons separate.
---

# Comparing terminal frontends

The [benchmark package](../packages/overlay_tui_bench/) measures the direct,
Lustre and signals frontends from the [terminal shell guide](./tui_shell.md).
From packages/overlay_tui_bench:

```sh
bun install
gleam build --warnings-as-errors
gleam run -- matrix
gleam run -- report
```

Run the matrix while builds, tests and recordings are idle. Each of 60 fresh
Bun processes mounts one frontend at 110×34 cells. Trials rotate frontend
order, use 20 or 200 history rows, warm up for 40 updates and retain 120 timed
native frames. Streaming appends Markdown to a busy response; typing uses
native mocked input, including highlighting and completion. Every trial checks
the final visible frame and retains its hash and raw latencies.

The [fresh report](../packages/overlay_tui_bench/results/summary.md) summarizes
five trial means and p95s per group. The min/max range shows observed trial
variation. Import time, startup, memory, model calls, emulator output and screen
refresh are excluded. Asynchronous parser work can outlast a frame, so these
are preview latencies. The [package README](../packages/overlay_tui_bench/README.md)
defines the exact boundary and metadata.

The [older four-way dataset](../packages/overlay_tui_bench/historical/README.md)
includes a TypeScript baseline from 4 October 2026. Its source revision and
driver differ; it is historical evidence and should not be pooled with fresh
results. Reconciliation strategy and row identity also differ between apps,
so these measurements do not isolate language or framework overhead.

The [checked recording](../packages/tracing/recordings/terminal-benchmarks.mp4)
runs the report after measurement and validates all 60 fresh plus 80 historical
trials from their saved samples. From packages/tracing,
gleam run -m tracing/terminal_benchmarks_demo repeats that check and records it.
The terminal shell guide supplies the actual interactive frontend recordings.
