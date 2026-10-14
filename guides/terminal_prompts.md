---
name: Editing CLI prompts
description: Edit terminal input, recall earlier lines, and preserve piped input for subsequent EYG effects.
---

# Editing CLI prompts

[Watch the checked terminal walkthrough](/glasshouse/cli-prompts.mp4).

Start the current [CLI](./install_from_source.md) with `eyg`. Type
`let answer = 43`, press Left then Delete, type `1`, and press Enter.
Enter `answer` to see `41`. Press Up then Enter to repeat that query.
`/t answer` reports `Integer`.

| Key | Action |
| --- | --- |
| Left / Right | move by one grapheme |
| Home / End, Ctrl-A / Ctrl-E | go to the start or end |
| Backspace / Delete | remove the previous or next grapheme |
| Up / Down | browse history and return to the unfinished draft |
| Ctrl-U / Ctrl-K | clear the line or its remaining suffix |
| Enter | submit the line |
| Ctrl-C, Ctrl-D on an empty line | end input |

Combining characters and emoji retain their boundaries while editing. History
lasts for the current invocation and includes EYG `Prompt` calls. An empty line
at the shell prompt exits the shell.

Piped input consumes one line per `Prompt`, accepting CRLF and a final line
without a newline. Later bytes remain available to subsequent prompts or
`StandardIn`. EOF and invalid UTF-8 return `Error({})`.

Gleam owns the editor and input decoding; `plinthx` binds native descriptor and
terminal operations. The [TUI guide](./tui_shell.md) covers syntax highlighting
and structural editing.

To reproduce the recording, build the host CLI, then run from `packages/tracing`:

```sh
EYG_BIN=/absolute/path/to/eyg gleam run -m tracing/cli_prompt_demo
```

It uses Xvfb, xterm, tmux and ffmpeg; install Symbola for the recorded emoji.
It checks actual results and records
`recordings/cli-prompts.mp4`. `packages/loam` tests the editor, split key
sequences and real processes consuming Unicode, EOF and remaining stdin.
