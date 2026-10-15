# Checks and recordings

Gleam programs that drive EYG tools as a person would and keep evidence of
what happened.

The [trajectory guide](../../guides/trajectories.md) covers recording in the CLI
and browser, offline replay, pi-mono/opencode formats and real backend checks.
The [performance viewer guide](../../guides/trace_performance.md) covers fresh
effect/function captures, offline flame charts, printable exports and Jaeger
verification. `gleam run -- capture`, `profile-capture`, `render` and `export`
are implemented by the Gleam tracing entrypoint. The checked presentation is
in [presentation](./presentation/index.html).

- `gleam run -m tracing/terminal_fixture`: scripted Ollama on 7206 for the
  [terminal shell guide](../../guides/tui_shell.md).
- `gleam run -m tracing/terminal_demo`: record and check `eyg tui` using Xvfb,
  xterm, tmux and ffmpeg. Checks archive closure, token usage and offline
  replay; records into `recordings/terminal-*`.
- `gleam run -m tracing/tui_check -- shell|overlay`: use `eyg tui` in tmux,
  typing keys and waiting at each check for text on the screen. Build
  packages/gleam_cli first. Packages come from a local hub on port 7207 and
  Overlay replies from a scripted model on 7206. Each checked screen and an
  asciinema cast are in `recordings/tui` and `recordings/tui-overlay`.
- `gleam run -m tracing/model_fixture`: scripted Ollama and built debugger on 7201.
- `gleam run -m tracing/artifact_check`: run both real artifact browser workflows
  against a caller-owned PostgreSQL database. Starts and stops the hub on 7812,
  Overlay on 5280 and the model fixture on 7201; saves checks under `.recordings`.
  See the [artifact guide](../../guides/overlay_artifacts.md) for setup.
- `gleam run -m tracing/browser_demo`: record the actual Overlay/debugger workflow
  and verify archive closure and all pinned runs. Requires Overlay on 5280 and
  the built website. It starts/stops its own fixture.
- `gleam run -m tracing/verify_backend`: upload the checked archive to Jaeger and
  query every span; `TRACE_BACKEND=langfuse` also checks types, grouping, models
  and token counts. `VERIFY_ONLY=true` skips upload.
- `gleam run -m tracing/package_fixture`: repository standard package and its
  pinned reference over a local HTTP hub on 7207.
- `gleam run -m tracing/cache_check`: start the package fixture, verify two
  independent compiled CLI processes, stop the fixture and verify offline reuse.
  Set `EYG_BIN` to select the compiled binary.
- `gleam run -m tracing/cli_prompt_demo`: check and record the CLI's terminal
  editing, Unicode and history. Set `EYG_BIN` to select the host CLI.
- `gleam run -m tracing/cli_interrupt_demo`: a delayed local model on7208 checks
  real Ctrl-C, a resumed prompt, signal cleanup and the saved closed trajectory.
- `gleam run -m tracing/openai_check`: real HTTP on7209 checks Chat Completions
  headers, fragmented tools, usage, the compiled CLI, archive closure and replay.
- `gleam run -m tracing/codex_config_check`: execute the guide configuration with
  a fake file cache and empty prompt; check redaction, archive closure and replay.

Fixtures and tests are Gleam. Playwright library adapters are in `gleam_playwright`;
base platform bindings are in `plinthx`. Successful recordings are in `recordings`;
failure diagnostics are ignored under `.recordings`.
