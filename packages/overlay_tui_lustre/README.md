# Lustre terminal frontend

The full terminal REPL and overlay agent expressed as Lustre elements and
rendered with `@opentui/core`. All new application and adapter code is Gleam.

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
`bun packages/overlay_tui_lustre/entry.mjs`.

`terminal_lustre/view` produces a complete virtual tree of native terminal
widgets. History rows use Lustre keys and memos. `terminal_lustre/render`
feeds successive trees through the actual `lustre/vdom/diff` and
`lustre/vdom/cache` modules. `terminal_lustre/adapter` applies their
Mount/Reconcile messages to retained OpenTUI objects. The shared controller
owns the interaction reducer and commands, including evaluator IPC.

The adapter handles insert, remove, replace, move, text and property updates,
fragments, mapped events and memo expansion. Its metadata tree preserves
virtual fragment/map boundaries separately from native children. This keeps
event paths correct after keyed moves, without adding layout boxes for
fragments. Native textarea focus is applied after visibility updates.

This is a terminal backend for Lustre's VDOM, not a browser DOM emulation.
It supports the terminal widget tags and properties used by this application;
HTML, CSS, arbitrary browser properties and event debounce/throttle are not
implemented. Constructor options are static; mutable properties have
explicit native setters. The adapter uses internal Lustre modules and pins
**5.7.1**, so a Lustre upgrade needs the adapter conformance suite.

The render loop is written in Gleam instead of using Lustre's JavaScript
server runtime. The pinned package's `runtime/server/runtime.ffi.mjs` has a
six-argument constructor called with five arguments in `start`, and two
dispatch branches declare `const { message } = message`, triggering a
JavaScript temporal-dead-zone error. Using the VDOM/cache modules directly
avoids modifying a dependency or adding a JavaScript runtime fork. There is
no independently implemented diff algorithm.

The same seven native workflow tests run against all Gleam frontends through
the shared test-file symlink. Adapter tests additionally verify real Lustre
keyed moves, memo reuse, native identity, resource disposal, fragments and
mapped mouse-event paths. OpenTUI bindings live in [`gleam_opentui`](../gleam_opentui/); other host
bindings use Plinth for Web APIs and Plinthx for Node/Bun APIs.
