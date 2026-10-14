# Trajectory checks

The [trajectory guide](../../guides/trajectories.md) covers recording in the CLI
and browser, offline replay, pi-mono/opencode formats and real backend checks.

- `gleam run -m tracing/model_fixture`: scripted Ollama and built debugger on 7201.
- `gleam run -m tracing/browser_demo`: record the actual Overlay/debugger workflow
  and verify archive closure and all pinned runs. Requires Overlay on 5280 and
  the built website. It starts/stops its own fixture.
- `gleam run -m tracing/verify_backend`: upload the checked archive to Jaeger and
  query every span; `TRACE_BACKEND=langfuse` also checks types, grouping, models
  and token counts. `VERIFY_ONLY=true` skips upload.
- `gleam run -m tracing/terminal_fixture`: scripted Ollama on 7206 for the
  [terminal shell guide](../../guides/tui_shell.md).
- `gleam run -m tracing/terminal_demo`: record and check the direct, Lustre and
  signals frontends using Xvfb, xterm, tmux and ffmpeg. Checks archive closure,
  token usage and offline replay; records into each frontend's `recordings`.

Fixtures and tests are Gleam. Playwright library adapters are in `gleam_playwright`;
base platform bindings are in `plinthx`. Successful recordings are in `recordings`;
failure diagnostics are ignored under `.recordings`.
