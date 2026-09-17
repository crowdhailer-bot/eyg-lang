# overlay_maintainer

An Overlay context for an agent that looks after its own tools. It extends
[overlay_librarian](../overlay_librarian/README.md): the agent finds libraries
and guides, reads Overlay's source to explain failures, suggests pull requests
only when the fault is in Overlay, EYG or a package, and keeps the notes of a
workspace.

| Field | What it does |
| --- | --- |
| `readme` | Instructions added to the system prompt, including when to suggest a pull request. |
| `libraries`, `guides` | As in overlay_librarian. |
| `source.map` | Files that explain how Overlay and EYG behave, as `{path, about}`. |
| `source.read(path)` | Fetch a file of github.com/CrowdHailer/eyg-lang, `Ok(text)` or `Error(reason)`. |
| `source.list(path)` | The entries of a directory, as `{path, type}`. |
| `workspace.notes({})` | Notes in `notes/`, as `{path, name, description, date}` from their frontmatter. |
| `workspace.write_note({name, description, date, body})` | Write `notes/<name>.md` with frontmatter. |

`workspace` uses the file effects, programs can only use it in sessions with a
workspace.

## Evaluate it

The `contexts` suite of `packages/overlay_eval` checks when pull requests are
suggested, on problems in Overlay and on mistakes in programs, and how notes
are kept.

```sh
# packages/overlay_eval
gleam run -m overlay/eval -- run suites/contexts.eyg --context ../../eyg_packages/overlay_librarian/index.eyg --context ../../eyg_packages/overlay_maintainer/index.eyg --model ollama:gpt-oss:120b --trials 3
```
