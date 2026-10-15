# Source-branch measurements

These 80 JSON trials and their summary are retained unchanged from source
commit 96c014fa. Their own metadata identifies the measured frontend revision
and 2026-10-04 timestamps. They compare TypeScript, direct Gleam, Lustre and
signals under the source branch's original driver.

They are historical evidence, not fresh measurements of roadmap. The current
Gleam runner separately measures the three current Gleam frontends, with a
different module-import policy and no import-time or memory comparison. Keep
the two datasets separate when interpreting results.

The [original driver](https://github.com/crowdhailer-bot/eyg-lang/blob/96c014fa/packages/overlay_tui_bench/bench.mjs)
documents how the source measurements were made. The current report checks the
complete historical matrix and recomputes each mean and p95 from its 120 samples.
