# Direct OpenTUI frontend

The terminal REPL and overlay agent written in Gleam, using retained
`@opentui/core` widgets directly. There is no JSX or rendering framework.

```sh
bun install
gleam run
gleam run -- overlay ../overlay_tui/examples/codex.eyg
gleam test
```

Watch the [REPL and structural editor](recordings/repl.mp4) and
[live overlay with code and effects](recordings/overlay.mp4).
The [HTML presentation](../overlay_tui_bench/presentation.html) compares all
three Gleam frontends with the original TypeScript/Solid implementation.
After building, run from the repository root with
`bun packages/overlay_tui_core/entry.mjs`.

Noninteractive commands use the existing CLI unchanged, for example
`gleam run -- eval -c '42'`. Interactive startup requires stdin and stdout
to be terminals. Run from the desired working directory when resolving
relative imports; Gleam's generated entry can also be launched with Bun.

`core/native_view` retains each history row by its run ID and explicitly
updates changed widget properties. It uses native Markdown, scrolling,
textarea editing, clipboard and mouse events. `core/controller` connects
the shared Gleam interaction model to the isolated evaluator process, owns
input and cleanup, and accepts a mount function for the other experiments.
`terminal/app` owns the application state without depending on OpenTUI.

The full structural editor still uses Morph's projection and operations.
F2 switches modes; F1 lists shortcuts; Ctrl+E opens effect logs; Ctrl+O opens
overlay tool code. Completion preserves Unicode text and the text after the
cursor. Prompt replies resume the evaluator without discarding a draft.

OpenTUI bindings live in [`gleam_opentui`](../gleam_opentui/); Web APIs use
[`plinth`](../plinth/) and Node/Bun APIs use [`plinthx`](../plinthx/). This package contains
Gleam application code only. Native options currently use JSON-compatible
OpenTUI properties, so malformed option values return binding errors at
runtime rather than Gleam compile errors.

The tests exercise real native terminal input, Unicode completion, resize,
effects, structural edits and undo/redo, prompts, Markdown streaming, and
responsive typing/shutdown while the evaluator runs indefinitely. Replay
ports isolate renderer tests from package discovery and external models;
integration tests use the real Gleam subprocess.
