# jev_playground

Jev, TypeSafe's decision model, writes EYG programs one structural edit at a time.
Each step Jev is shown the task, the program with the selection marked `«like this»`,
type errors, test results and every edit possible at the selection, and chooses one.
Jev cannot generate text, so names and literals are offered from the task, the program and a few common names.

## Modules

| Module | Purpose |
| --- | --- |
| `action` | Every edit as data, each a `morph/buffer` transformation or navigation. `perform` applies it, moving to the next `?` after a hole is filled. |
| `options` | The actions available at the selection with a description for Jev, limited to the 255 a choice accepts. |
| `vocabulary` | Names, labels, strings and numbers offered for edits that need text. |
| `agent` | Builds the state and question for a step and applies the chosen action. No IO. |
| `run` | Evaluates programs, resolving library references, and runs their `tests`. |
| `synthesis` | Finds the actions that build a target program, used for demos and research. |
| `mock` | Stands in for Jev when replaying a script. |
| `demo` | Scripted runs, each a task and the program Jev should reach. |
| `client` | Sends requests with fetch, directly or through the dev server proxy. |
| `app`, `view`, `web` | The Lustre page. |

A test is a record `{name, test}` in the `tests` list of the program, it passes when `test({})` returns `True({})`.

## Running

Install the JavaScript dependencies, needed for bundling and recording, then bundle and serve.

```sh
bun install
gleam run -m jev_playground_build --runtime bun
TYPESAFE_API_KEY=... gleam run -m jev_playground_dev --runtime bun
```

Open http://localhost:8095 to give Jev a task, the dev server proxies `/v1/..` to TypeSafe adding the key.
http://localhost:8095/demo/github replays a demo with mocked answers, `?speed=2` halves the thinking time.

Record a demo, playwright needs Node rather than Bun.

```sh
gleam run -m jev_playground/record -- video "/demo/github?speed=1.5" recordings/github-client.mp4
```

`gleam run -m jev_playground/solve --runtime bun -- "task" 20` lets Jev work on a task in the terminal.

## Notes

- Use Bun for anything calling the API, Node's fetch took several seconds per request from this machine.
- The dev server serves a bundle built ahead of time. Bundling on each request used 400MB,
  and on a small host the kernel then kills the recording browser.
