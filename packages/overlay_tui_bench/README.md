# Terminal comparison benchmarks

Open [presentation.html](presentation.html) locally for the standalone slide
deck, interactive benchmark charts, architecture diagrams and six recordings.
The recommendation is the direct `@opentui/core` Gleam frontend: its retained
rows improve streaming over the current baseline with the smallest new
rendering abstraction. The original TypeScript frontend remains faster for
typing and history creation. Stable per-row identity could also improve the
original; these results do not establish a language-wide speed advantage.

Build the original `overlay_tui` package first, then:

```sh
bun install
gleam build --warnings-as-errors
bash run.sh
bun report.mjs
bun build-presentation.mjs
```

`bench.mjs` is a single driver for the unchanged TypeScript/Solid application
and the three generated Gleam frontends. Each trial runs in a fresh Bun
process. The baseline adapter lives next to the original application so it
uses the same Solid and OpenTUI module instances. `src/benchmark.gleam`
exposes the typed Gleam controller to that driver. These adapters contain no
new application behavior. OpenTUI foreign declarations live in `gleam_opentui`; Web APIs use Plinth
and Node/Bun APIs use Plinthx.

The matrix runs five trials in rotating order for each frontend, workload,
and history size (20 or 200 completed tool rows). All use OpenTUI 0.5.14,
110×34 cells, the same event JSON, and a native frame per update. Forty updates
warm up each workload; the next 120 produce the latency samples.

- **Streaming:** successive Markdown chunks in one growing assistant response,
  while a submitted request remains busy. The Markdown parser is initialized
  and preloaded before the workload. The final frame must contain chunk 159.
- **Typing:** the same characters entered through native mocked terminal input
  in REPL mode, including completion and syntax highlighting. The final frame
  must contain the typed expression.

Latency covers event decoding/input, application update, reconciliation and
the requested native frame. It does not include a real terminal emulator,
display refresh, network/model latency, or evaluation. Syntax highlighting
runs asynchronously in OpenTUI; frame latency measures its streaming preview,
not completion of every parser job. Parser work is drained before shutdown.
Do not run recording, builds or other benchmarks concurrently with the matrix.

`import_ms` measures importing the frontend renderer modules inside an
already running Bun process, not cold process startup. `mount_ms` measures
creating the test renderer, mounting the app, and its first frame.
`history_ms` includes adding completed tool rows and one frame. Memory is
process RSS and JavaScript heap usage sampled after parser draining and
renderer teardown, without forced garbage collection. It includes native
allocations and should be interpreted across repeated trials; it does not
measure peak memory or retained live application size.

Results retain every latency sample, machine/runtime information and a final
frame hash. The shell runner only orchestrates fresh processes; EYG has no
shell/process-spawn effect. Compile and install time are excluded.

The checked-in matrix was recorded on 2026-10-04 with Bun 1.3.14 on Linux x64
(AMD EPYC-Genoa), after building with Gleam 1.16.0. `report.mjs` requires all
80 trials and aggregates medians of the five trial means/p95s. Mean ranges
are observed trial variation, not confidence intervals. All final stderr
logs were empty. The original application replaces streamed entry objects,
while the alternatives retain native widgets by run ID; this difference is
part of the comparison, not isolated rendering-framework overhead.

The final matrix records its source revision in each JSON trial and was
rerun after integrating `overlay-review` at `d27244a`. The six recordings
were captured before that integration, on the `05a4ed1` upstream base;
the frontend rendering implementations did not change during the merge.

`record.sh` creates six real terminal recordings using Xvfb, xterm, tmux and
FFmpeg. Build all three frontends first. It uses the existing Codex example
and requires a working local login. The script owns a separate display and
tmux session; it stops those and its recording processes on exit.
The videos show arithmetic, bindings, stdout, type inspection, structural
integer editing and undo/redo, then a live overlay run with code/effect views.

The checked-in measurements predate the `gleam_opentui` extraction and the
latest eval/artifact integration. They describe that recorded revision, not a
fresh measurement of this checkout. Run the matrix above to measure changes.
