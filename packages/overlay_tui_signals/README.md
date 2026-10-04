# Gleam signals frontend

The complete terminal REPL and overlay agent with a synchronous signal graph
implemented in Gleam. It uses `@opentui/core` without Solid or JSX.

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
`bun packages/overlay_tui_signals/entry.mjs`.

`signals/reactive` tracks reads dynamically, removes obsolete dependencies,
caches lazy memos, batches writes, and runs owned effects in creation order.
Invalidation reaches the whole dependent graph before effects run. Effects
pull dirty memos, so a diamond dependency cannot expose a mixture of old and
new values. Nested computations and cleanup belong to scopes; disposal also
prevents already queued callbacks from running.

`signals/keyed` keeps each row's signal, scope and native node when its key
survives an update or move. Removing a row disposes subscriptions and native
resources. `signals/view` publishes screen state and individual history
entries in one batch. An assistant chunk updates its row; completed history
rows do not run again. Only assistant Markdown subscribes to the global
streaming flag.

Widget construction and property setters are shared with
[`overlay_tui_core`](../overlay_tui_core/) to keep appearance and interaction
comparable. This experiment binds at the screen and history-row level; it
does not reproduce a JSX compiler's automatic binding of every expression.
The graph is reusable without OpenTUI, but it is an experiment rather than a
complete replacement for Solid: there are no transitions, suspense,
resources or error boundaries, and unchanged memo results may still wake a
subscribed effect after invalidation.

OpenTUI bindings live in [`gleam_opentui`](../gleam_opentui/), Web APIs in
[`plinth`](../plinth/) and Node/Bun APIs in [`plinthx`](../plinthx/). The native conformance
tests are shared by a test-file symlink with the direct frontend, selecting
this mount function through `test_frontend`. Additional tests check diamonds,
dynamic dependencies, nested cleanup, batching, queued disposal and keyed
identity.
