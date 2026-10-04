# EYG terminal interface

The new CLI uses Bun, OpenTUI and SolidJS, matching
[OpenCode's terminal stack](https://github.com/anomalyco/opencode/tree/dev/packages/tui).
Run it from any working directory after building:

```sh
cd packages/overlay_tui
bun install --frozen-lockfile
bun run build
bun run dev
```

From the repository root: `bun packages/overlay_tui/src/main.ts`.
Optionally run `bun link` in this package to install the `eyg-tui` command.
The build output and dependencies must remain alongside the source entry point.
All arguments accepted by [`gleam_cli`](../gleam_cli/README.md) use its existing
parser and command handlers. Piped input preserves the original CLI behavior.

The interactive text REPL runs the existing shell in a separate Bun process, keeping the
terminal responsive during evaluation. Bindings, hub imports, local imports,
shell configs, `/scope`, and `/type` use the same runtime as the original CLI.
Package names load asynchronously from `EYG_ORIGIN` (default `https://eyg.run`).
Only referenced modules are fetched. File suggestions are relative to the
session's current directory.

| Key | Action |
| --- | --- |
| Enter | Evaluate or answer a runtime input request |
| Shift+Enter / Alt+Enter | Insert a newline |
| Tab | Accept the highlighted completion |
| Up / Down | Select a completion |
| Escape | Dismiss completion |
| Ctrl+E | Expand the most recent run's effect and hub request log |
| Ctrl+O | Expand the most recent overlay tool's code |
| PageUp / PageDown | Scroll history |
| F1 | Toggle help |
| F2 | Switch between text and structural editing |
| Ctrl+C / `/exit` | Exit the frontend |

Click a run's effect summary to expand or collapse it.

Structural mode uses the web workspace's Morph buffer, transformations, type
inference, and projection renderer. F2 imports the text draft on first entry;
subsequent switches preserve both drafts. Changing the text draft replaces the
structural draft on the next switch. Escape cancels a picker or returns to text.
Both modes share evaluated bindings and `/type` definitions. Structural code
executes directly as IR, so binary values and vacant nodes survive editing and
clipboard round trips. The display follows the web projection, including its
abbreviated package references; copying uses the full DAG JSON representation.

| Structural keys | Action |
| --- | --- |
| Arrows / Space / a | Navigate / next vacant node / increase selection |
| i / d / z / Z | Edit selected text / delete / undo / redo |
| n / s / b / v | Integer / string / binary / variable |
| f / c / C / w | Function / call with inferred arity / call once / call with selection |
| e / E | Assign / assign before |
| l / L / r / R | List / empty list / record / empty record |
| g / o / t / m | Field / overwrite / tag / match |
| p / h / j | Perform / handle / builtin |
| @ / # | Published package / content reference |
| q / Q | File import with completion from the working directory |
| x / < / > | Spread / insert before / insert after |
| y / Y | Copy / paste the selected expression |
| k / Enter | Toggle folding / evaluate |

Click a node to select it. Up at the root recalls the last evaluated structure;
Down returns to the current draft. Suggestions include variables, fields,
variants, builtins, and the CLI runtime's effects. References load in the
background to supply field and type hints. File imports retain their paths;
the package picker pins the selected published release, as the web editor does.
Clipboard access uses OpenTUI's host clipboard and OSC52, with an in-session
fallback; terminal paste also accepts EYG text or DAG JSON. The web workspace's
`u` signing popup is still a placeholder and is identified as such in the TUI.

`bun packages/overlay_tui/src/main.ts overlay path/to/.overlay.eyg` starts a
conversation using the same provider configuration and policies as the existing
overlay command. Assistant replies stream into the conversation. Each tool has
an independently collapsible code view and effect log, including policy
decisions and returned values. Policy questions and `StandardIn` are answered
in the composer; an unsent draft is preserved while answering. `/export [path]`
retains the existing OpenCode-compatible session export.

Development checks: `bun run build`, `bun run typecheck`, and `bun test`.
The tests include actual OpenTUI keyboard input, resize behavior, and EYG
evaluation. The terminal test session is separate from the user's tmux session.

Watch the recorded demonstrations:

- [Text and structural REPL](recordings/repl.mp4): package completion and actual
  hub/module requests, bindings, effects, file completion, structural selection,
  integer editing, undo/redo, and constructing an effect call (57 seconds).
- [Live overlay session](recordings/overlay.mp4): a streamed Codex conversation,
  collapsed and expanded tool code, and policy/effect results (47 seconds).

The overlay recording uses [examples/codex.eyg](examples/codex.eyg), which reads
an existing local Codex login and grants only standard output and clock effects.
It neither creates nor refreshes credentials. Use an existing overlay provider
configuration for other providers.

Evaluation and structural work run in a separate Bun process. Rendering, scrolling and text
entry remain on the UI thread; a regression test types and renders within
250 ms while EYG runs an infinite computation. Noninteractive commands load
without the renderer. On the development machine (Linux, Bun 1.3.14), eight
fresh `eval -c 42` processes measured 111 ms median and 121 ms maximum. These
measurements describe this machine, not a timing guarantee. Starting and
initializing the interactive runtime measured 132 ms median across eight
processes (148 ms maximum, before fetching the package index). Process isolation
also avoids [Bun's worker shutdown race with pending network requests](https://github.com/oven-sh/bun/issues/38519).

Command parity tests compare stdout, stderr and exit status against the original
CLI for execution, checking, compilation, parsing, piped input, help and errors.
Hub publishing and signatory operations delegate to the original handlers too;
tests do not publish or mutate accounts.
