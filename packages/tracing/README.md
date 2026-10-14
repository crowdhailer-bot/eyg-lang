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
- `gleam run -m tracing/package_fixture`: repository standard package and its
  pinned reference over a local HTTP hub on 7207.
- `gleam run -m tracing/erlang_demo`: record the real Erlang console, verify
  package requests stop after caching, run counters and check errors before effects.
- `gleam run -m tracing/phoenix_demo`: check and record the Phoenix example on
  7815 with `package_fixture` on 7207. Covers the real editor and LiveView effects.
- `gleam run -m tracing/ash_demo`: check and record AshAdmin on 7816 with the
  package fixture. Covers highlighting, host actions, type errors and cache reuse.
- `gleam run -m tracing/cache_check`: start the package fixture, verify two
  independent compiled CLI processes, stop the fixture and verify offline reuse.
  Set `EYG_BIN` to select the compiled binary.
- `gleam run -m tracing/cli_prompt_demo`: check and record the CLI's terminal
  editing, Unicode and history. Set `EYG_BIN` to select the host CLI.
- `gleam run -m tracing/cli_interrupt_demo`: a delayed local model on7208 checks
  real Ctrl-C, a resumed prompt, signal cleanup and the saved closed trajectory.
- `gleam run -m tracing/openai_check`: real HTTP on7209 checks Chat Completions
  headers, fragmented tools, usage, the compiled CLI, archive closure and replay.

Fixtures and tests are Gleam. Playwright library adapters are in `gleam_playwright`;
base platform bindings are in `plinthx`. Successful recordings are in `recordings`;
failure diagnostics are ignored under `.recordings`.
