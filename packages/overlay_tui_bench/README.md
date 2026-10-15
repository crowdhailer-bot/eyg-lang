# Native terminal comparison

This Gleam runner compares the direct, Lustre and signals frontends using
OpenTUI 0.5.14's real test renderer and mocked terminal input. The
[guide](../../guides/terminal_benchmarks.md) explains the measurements and
links the checked recording. The [fresh summary](results/summary.md) retains
the raw samples beside it; [historical](historical/) keeps the source branch's
four-way comparison, including its TypeScript baseline.

```sh
bun install
gleam build --warnings-as-errors
gleam run -- matrix
gleam run -- report
```

Run the matrix without concurrent builds, tests, recordings or other benchmarks.
It starts one fresh Bun process per trial, rotates frontend order over five
trials, and runs streaming and typing with 20 and 200 completed tool rows.
Every trial warms up for 40 native frames, measures 120 more, verifies its final
frame and saves every sample plus a SHA-256 of that frame. Parser preload is
outside measured streaming updates; asynchronous syntax work can continue after
a frame. Draining and teardown occur before the process exits.

Each trial imports all three frontend libraries before measuring the selected
mount. Import time, cold startup and memory are excluded. Latency covers the
event/input, application update, reconciliation and requested native frame;
it excludes model/network time, evaluation, emulator output and screen refresh.

The report validates all 60 fresh and 80 historical trials, rejects incomplete
or duplicate groups, and recomputes the reported means and p95s from samples.
It summarizes medians of five trial means and five trial p95s. The range is
observed variation, not a confidence interval. A smaller frame time does not
establish language-wide or isolated framework speed: row retention and other
application choices are part of these frontends.

Frontend revision is in results/frontend-revision.txt. It identifies the
committed frontend sources measured by the new runner; the runner itself is
in this commit. Each fresh JSON records runtime, CPU, native library version,
timestamp, trial identity and samples. Per-trial stderr is kept in ignored
results/*.log files for inspection.

One trial can be repeated with
`gleam run -- trial core stream 20 1`; variants are core, lustre and signals,
and workloads are stream and typing. Node cannot run the native Bun renderer.
