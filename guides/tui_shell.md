---
name: Terminal EYG shell
description: Evaluate highlighted EYG, edit its structure, and inspect recorded Overlay tools in a terminal.
slug: tui-shell
---

# Terminal EYG shell

[Watch the shell and structural editor](/glasshouse/terminal-repl.mp4).
[Watch Overlay, tool code and effects](/glasshouse/terminal-overlay.mp4).
The [recordings](../packages/tracing/recordings/) include the checked
trajectory.

`eyg tui` runs the shell full screen in a terminal. From the repository root:

```sh
cd packages/gleam_cli
gleam run -- tui
```

Relative imports resolve from the launch directory. The shell runs in the same
process as the screen, which advances an evaluation a slice at a time, so typing
and scrolling stay responsive while effects are performed. A pure loop stops at
the interpreter's reduction limit with an `ExecutionLimit` effect.

Enter `!int_add(20, 22)` to see `42`. Then enter `let answer = 40` and
`!int_add(answer, 2)`. Scope survives between inputs. `/scope` lists bindings;
`/type answer` displays `Integer`. Text, structural code and completed inputs
have syntax highlighting. Tab completes packages after `@` and files in imports;
Up/Down select a completion and Escape dismisses it.

Enter `perform StandardOut("Hello from Gleam")`, then press Ctrl+E to inspect
the request and reply. Interactive `StandardIn` prompts resume the same
evaluation; your draft remains available afterward.

The same tui runs on the BEAM from `packages/eyg_tui` with `gleam run`. There
it has no network access, so hub packages and Overlay are unavailable; quit
with `/exit`, as Ctrl+C is the VM's break signal.

## Edit the structure

Type `!int_add(20, 22)` without submitting, then press F2. Press Right twice to
select `20`, press `n`, enter `40` and submit. `z` undoes the edit and `Z` redoes
it. Enter evaluates the structural program and returns `62`.

Structural shortcuts match the web editor and use its Morph operations:

| Keys | Action |
| --- | --- |
| Arrows, `a`, Space | Navigate, select parent, jump to a vacant node |
| `n`, `s`, `b`, `v` | Integer, string, binary, variable |
| `f`, `c`, `C`, `w` | Function, call, single call, call with this term |
| `e`, `E`, `l`, `L`, `r`, `R` | Assignment, list, record |
| `g`, `o`, `t`, `m`, `x` | Field, overwrite, tag, match, spread |
| `p`, `h`, `j`, `@`, `#` | Effect, handler, builtin, package, content reference |
| `<`, `>`, `d`, `i`, `k` | Insert before/after, delete, edit, fold |
| `y`, `Y`, `z`, `Z` | Copy, paste, undo, redo |

`q`/`Q` choose a local file. F1 shows help; F2 switches text/structure. Escape
dismisses a picker or returns to text. Enter submits; Alt+Enter adds a text
newline. Ctrl+E opens effects, Ctrl+O opens Overlay tool code, PgUp/PgDn scroll,
and Ctrl+C quits.

## Run Overlay

In another terminal, start the checked local model fixture:

```sh
cd packages/tracing
gleam run -m tracing/terminal_fixture
```

From `packages/gleam_cli`:

```sh
gleam run -- tui overlay ../tracing/fixtures/tui/local.eyg
```

Send `Print a greeting and calculate 20 plus 22.` The fixture returns one EYG
tool call, prints the greeting and computes `42`. Ctrl+O reveals the program;
Ctrl+E reveals the policy decision and effect reply. For a real model, use an
[Overlay configuration](./trajectories.md) with its provider and effect gates.

Every completed turn saves a Glasshouse archive under `.eyg/traces`. It contains
model requests, raw responses, usage, pinned programs and effect journals.
`eyg inspect <path>` and `eyg replay <path>` work as for ordinary CLI traces;
replay uses recorded effects. `/export <path>` exports the conversation.

To reproduce the recordings, install Xvfb, xterm, tmux and ffmpeg, then run
`gleam run -m tracing/terminal_demo` from `packages/tracing`. It checks visible
results, the complete archive, token usage and offline replay, and stops its
own fixture and terminal processes.
