# jev_playground

Jev, TypeSafe's decision model, writes EYG programs one structural edit at a time.
Each step Jev is shown the task, the program with the selection marked `«like this»`,
type errors, test results and every edit possible at the selection, and chooses one.
Jev cannot generate text, so names and literals are offered from the task, the program and a few common names.

## Modules

| Module | Purpose |
| --- | --- |
| `action` | Every edit as data, each a `morph/buffer` transformation or navigation. `perform` applies it, moving to the next `?` after a hole is filled. |
| `options` | The actions available at the selection with a description for Jev, limited to the 255 a choice accepts. `Config` holds every way of offering them. |
| `vocabulary` | Names, labels, strings and numbers offered for edits that need text. |
| `agent` | Builds the state and questions for a step and applies the chosen actions. No IO. |
| `environment`, `library` | The effects, libraries and scope a program is checked and run in. |
| `dnsimple` | A DNSimple account served from memory, for evals that use the DNSimple context. |
| `run` | Evaluates programs, resolving library references, and runs their `tests`. |
| `synthesis` | Finds the actions that build a target program, used for demos and research. |
| `compound` | Compound moves mined from `eyg_packages`, see [compound moves](./research/compound_moves.md). |
| `mock` | Stands in for Jev when replaying a script. |
| `demo` | Scripted runs, each a task and the program Jev should reach. |
| `eval` | Tasks with a starting program and a checker, and the variants they are run with. Twenty ask about a DNSimple account. |
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

## Evals

An eval runs Jev against the real API until its checker accepts the program or the step budget runs out.
Every step is saved to `recordings/evals`.

```sh
TYPESAFE_API_KEY=... gleam run -m jev_playground/evaluate --runtime bun -- list-functions-scaffold compounds holes
TYPESAFE_API_KEY=... gleam run -m jev_playground/sweep --runtime bun -- compounds [eval ...]
```

The flags of a variant are listed at `eval.variant`, `sweep` runs every eval with a set of variants and writes a table.
An eval with a context fetches it from the hub by content id, `EYG_HUB` sets the hub, `http://localhost:8080` by default,
and runs in the browser environment the overlay page gives, see [contexts](./research/contexts.md).
`dnsimple` in the list of evals stands for the twenty questions about a DNSimple account.
Jev mostly answers the same request the same way but close calls flip, `repeat=3` runs each eval and variant three times.
A run stops after three choices in a row below 0.2 confidence, which 1 of 357 solved runs did.
http://localhost:8095/eval/<file> replays a saved run, named without `.json`, at the speed Jev answered, the [evals](./research/evals.md) have the results.

## Recording

Playwright needs Node rather than Bun.

```sh
gleam run -m jev_playground/record -- video "/demo/github?speed=1.5" recordings/github-client.mp4
gleam run -m jev_playground/record -- screenshot "/demo/github" recordings/github.png
gleam run -m jev_playground/record -- sample "/demo/github" 30
gleam run -m jev_playground/record -- inspect "/demo/github" "document.title"
```

`sample` prints the step and status every two seconds and long tasks, `inspect` evaluates an expression once the run finishes.

## Other tools

| Command | Purpose |
| --- | --- |
| `solve -- "task" 20` | Jev works on a task in the terminal. |
| `mine` | Mines compound moves from `eyg_packages`. |
| `demos` | Counts the steps and compound moves of each demo. |
| `profile -- http 40` | Times each part of replaying a demo. |
| `api -- standard` | Prints the API of a library as Jev sees it. |
| `runs -- <since>` | Replays eval runs saved since a time and reports navigation and confidence. |

Each is `gleam run -m jev_playground/<command> --runtime bun`.

## Notes

- Use Bun for anything calling the API, Node's fetch took several seconds per request from this machine.
- The dev server serves a bundle built ahead of time. Bundling on each request used 400MB,
  and on a small host the kernel then kills the recording browser.
- `gleam run` exits 0 when the kernel kills the process for memory. Calling `main` of the compiled module in `build/dev/javascript`
  from a file run with `bun` shows the real status, 137.
  The host is shared and has under 4GB, avoid building or recording while a sweep runs.
- `eyg_ir` rewrites trees in continuation passing style, which overflows the browser stack on a library the size of `@standard`,
  `library.annotate` walks the tree directly instead.
