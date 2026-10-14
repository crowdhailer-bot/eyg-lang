# Checks and recordings

Gleam programs that drive EYG tools as a person would and keep evidence of
what happened. The [trajectory guide](../../guides/trajectories.md) covers
recording in the CLI and browser, offline replay, pi-mono/opencode formats and
real backend checks.

- `gleam run -m tracing/tui_check`: use `eyg tui` in tmux, typing keys and
  waiting at each check for text on the screen. Build packages/gleam_cli first.
  Packages come from a local hub on port 7207. Each checked screen and an
  asciinema cast are in `recordings/tui`.
- `gleam run -m tracing/model_fixture`: scripted Ollama and built debugger on 7201.
- `gleam run -m tracing/browser_demo`: record the actual Overlay/debugger workflow
  and verify archive closure and all pinned runs. Requires Overlay on 5280 and
  the built website. It starts/stops its own fixture.
- `gleam run -m tracing/verify_backend`: upload the checked archive to Jaeger and
  query every span; `TRACE_BACKEND=langfuse` also checks types, grouping, models
  and token counts. `VERIFY_ONLY=true` skips upload.

Fixtures and tests are Gleam. Playwright library adapters are in `gleam_playwright`;
base platform bindings are in `plinthx`. Successful recordings are in `recordings`;
failure diagnostics are ignored under `.recordings`.
