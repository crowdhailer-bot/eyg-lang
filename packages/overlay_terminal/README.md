# Shared terminal runtime

Gleam application logic shared by the terminal frontend experiments. It runs
the existing EYG shell and overlay agent, retains scope and policy state,
streams assistant messages, and handles structural editing through Morph.

`terminal/app` is the pure interaction reducer shared by the Gleam frontends.
`terminal/completion` handles package, file and structural-picker completion;
`terminal/highlight` provides tokens with native Unicode character offsets.
The frontends choose how state changes update native widgets.

```sh
gleam build --warnings-as-errors
gleam test
```

`terminal/repl` and `terminal/overlay` can run in a test process with typed
event and prompt callbacks. `terminal/process` runs them in a separate Bun
process for an interactive frontend. The command queue is implemented in
Gleam; prompt replies bypass it so an evaluation waiting for input can resume.
The two-line `worker.mjs` only invokes the generated Gleam entry point.

`terminal/protocol` defines events and requests with JSON encoders and
decoders. IPC carries JSON strings so generated Gleam constructor layouts do
not become a cross-process contract. Decoding happens at each receiving edge.

`terminal/driver` interprets the typed Loam effect variants. The frontend owns
terminal output and prompts; each other operation uses Loam's existing
executor. Fetch logs exclude credentials, query strings and fragments. No new
EYG effects are introduced.

`tui/structural` and `tui/bridge` are also used by the original TypeScript
frontend. `terminal/projection` translates Morph's Lustre projection into
terminal chunks with selection, error marks, indentation and clickable paths.
Evaluation consumes structural IR directly, preserving binary and vacant
nodes. Reference discovery runs independently; revision checks prevent a
late discovery result replacing a newer execution cache.

Host bindings live in [`gleam_opentui`](../gleam_opentui/) for OpenTUI,
[`plinth`](../plinth/) for Web APIs and [`plinthx`](../plinthx/) for Node and Bun. The mutable reference
in `terminal/cell` is an application abstraction over a native array binding.
This package contains no foreign function declarations.

The original `overlay_tui` keeps its TypeScript runtime and Solid UI for
comparison. Both depend on the same local EYG language packages, including
the latest merged `overlay-review` type-rendering changes. This prevents a
published package version from making the runtime comparison inconsistent.
