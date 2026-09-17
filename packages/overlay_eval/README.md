# overlay_eval

Evals for Overlay agents and the contexts they run with.

A session under eval is Overlay's own state machine, the one the browser runs.
Overlay returns all of its input and output as effect values, so the runner
performs them against fixtures instead of the world: a hub serving the
repository's packages, the guides of eyg.run, and the repository itself as it
appears on GitHub. Nothing about the agent changes, so an eval measures the
agent people use.

## Run

```sh
# every task solved by its reference solution, and failed by an agent that
# does nothing, no model needed
gleam run -m overlay/eval -- validate suites/contexts.eyg

# a model, three trials of each task, judged checks graded by another model
OLLAMA_API_KEY=... gleam run -m overlay/eval -- run suites/contexts.eyg \
  --context ../../eyg_packages/overlay_librarian/index.eyg \
  --model ollama:gpt-oss:120b --judge mistral:mistral-medium-latest --trials 3

# two contexts on the same tasks, with a comparison
gleam run -m overlay/eval -- run suites/contexts.eyg \
  --context none --context ../../eyg_packages/overlay_maintainer/index.eyg \
  --model ollama:qwen3.5:397b --trials 5
```

| Option | |
| --- | --- |
| `--context <path>` | An EYG module used as the session's context, `none` for Overlay's default. Repeat it to compare contexts. |
| `--model <model>` | `scripted:oracle`, `scripted:null`, `ollama:<name>` (Ollama Cloud, `OLLAMA_API_KEY`), `ollama-local:<name>` or `mistral:<name>` (`MISTRAL_API_KEY`). |
| `--judge <model>` | The model for judged checks. Use a different family to the agent. |
| `--trials <n>` | Trials of each task, for pass@k and pass^k. |
| `--tag <tag>` | Only tasks with the tag, repeatable. |
| `--root <path>` | The repository the fixtures are built from, default `../..`. |
| `--out <path>` | Where reports are written, default `evals`. |
| `--record <path>` / `--replay <path>` | Record model exchanges to cassettes, or answer from them. `--lenient` replays after a session has changed. |

A run writes `run.json`, `summary.md` and a markdown file for each trial.
`compare a/run.json b/run.json` prints the paired difference of two logs.

## Write a task

A suite is an EYG module whose fields are tasks, each task a record. Records,
not a list, so tasks can expect values of different types.

```eyg
{
  description: "Find the json package and decode a nested field.",
  tags: ["libraries"],
  prompts: ["An API returned {\"user\": {\"id\": 7}}. Run a program for the id."],
  checks: [Computes(7), References("json")],
  reference: [[Run("..."), Say("The user's id is 7.")]]
}
```

| Field | |
| --- | --- |
| `description` | What the task is for, shown in reports. |
| `prompts` | What the person says, each sent once the agent has finished the turn before. |
| `checks` | How the transcript is graded, see below. |
| `reference` | A solution, replies per turn of `Run(code)` and `Say(text)`. The oracle model follows it. |
| `tags` | Groups tasks, reported per tag and selected with `--tag`. |
| `workspace` | `{path, contents}` files, sessions without one cannot use file effects. |
| `routes` | `{url, status, body}` answered to GET, for services a task needs. |
| `max_model_calls` | The trial stops after this many, default 20. |

### Checks

Deterministic, from the transcript:

| Check | Passes when |
| --- | --- |
| `Computes(value)` | A program computed this EYG value. |
| `Satisfies({description, check})` | A program computed a value the EYG function accepts. |
| `References("json")` | A program referenced the package, found in the program's syntax tree. |
| `ReadsContext(["libraries", "search"])` | A program read that field path of its context. |
| `Fetches("/guides/json")` | A program fetched a URL containing this, successfully. |
| `Says("pull request")` / `NeverSays(...)` | The agent's replies contain the text, ignoring case. |
| `FileContains({path, text})` / `NoFile(path)` | About a file the session left behind. |
| `FileSatisfies({path, description, check})` | A workspace module's value is accepted by the EYG function. |
| `AnyFileContains({directory, text})` / `NoFileContains(...)` | About any file in a directory, for notes the agent names itself. |
| `WorkspaceUnchanged({})` | The workspace ends as it started. |

Judged, by a model:

| Check | |
| --- | --- |
| `Judged("The answer shows ReadFile with an offset and a limit.")` | One criterion, the judge answers pass, fail or unknown. |

Grade outcomes, not the path an agent took: prefer the value it computed, the
file it left or what it said over the tool calls it made. Use a judge for what
code cannot check, one criterion at a time.

### Validity

`validate` runs two agents over every task:

- the **oracle** follows the task's reference solution, it must pass every
  deterministic check, or the task is not solvable or a check is wrong,
- the **null agent** answers without running anything, it must fail, or the
  task can be passed without doing the work.

It runs in CI, and needs no model.

## Reports

Each task reports the trials it passed, `pass@k` (any trial passes) and
`pass^k` (every trial passes, the reliability that matters for something people
depend on), the share of checks passed, model calls and how many programs
failed to run. The suite reports the mean over tasks with a 95% interval; trials
of one task are not independent, so the error is computed from per task means.
Comparisons pair tasks across runs, which removes the variation between tasks.

## Cassettes

`--record` keeps the model's side of each trial and `--replay` returns it, so a
run can be graded again, or a change to the harness checked, without a model. A
replayed request that differs from the recording fails: the prompt, the context
or a tool result changed, and the recording is stale.
