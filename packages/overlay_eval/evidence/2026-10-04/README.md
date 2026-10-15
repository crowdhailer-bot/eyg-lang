# Live overlay evaluation on 4 October 2026

Historical evidence retained from source commit `96b20fcc`. These are the
source branch's recorded results, not new live calls during consolidation.
Current prompts and guide bodies have changed, so strict replay can reject
these recordings. Lenient replay inspects the old responses; it does not
measure the current prompt or the model's present reliability.

On 2026-10-15 the retained cassettes were replayed leniently against the current
runner, with no credentials or model requests: 10/12 passed with 51 model
exchanges. The exponential Fibonacci program in trial 3 exhausted the current
one-million-reduction limit; the original record-update failure remained.
The archived 11/12 below describes the source runner before that work bound.
The [bounded replay report](./replay-bounded/summary.md) includes all 12 new
transcripts and its machine-readable log.

All runs used Ollama Cloud `gpt-oss:120b`, the same four tasks in
[`suites/programs.eyg`](../../suites/programs.eyg), three fresh trials per task,
no context module and no model judge. Checks compare returned EYG values; the
word-count task also checks the final reply. Printing an answer and returning
`{}` does not satisfy a returned-value check. Expected values are not included
in model requests. The suite's reference and null-agent validation passes.

| Prompt | Passed | Model calls | Total trial time | Calls per passing trial |
| --- | --- | --- | --- | --- |
| Baseline | 7/12 | 49 | 55.644 s | 7.00 |
| Compact reference, rejected | 5/12 | 63 | 117.534 s | 12.60 |
| Explicit execution, retained | 11/12 | 51 | 64.044 s | 4.64 |

The baseline was the integrated overlay at `50446f2`. The retained change tells
the agent to execute when asked, return the requested value as its final
expression, and reread the syntax guide after a syntax error. The run tool's
description explains that Print returns `{}`. The mandatory syntax-guide step
remains. The compact reference removed that step; repeated invalid syntax and
answers without execution made it worse, so it was discarded.

This is a small development comparison, not a general reliability or speed
estimate. We selected the retained prompt using these tasks; this is not a held-out
evaluation. The final run still missed one record-update task by answering
without execution. It used slightly more calls and wall time overall, while
returning the correct values in four more trials. Per-trial medians were 4.452 s
for the baseline and 4.425 s for the retained prompt; these do not establish a
latency improvement. There were no provider failures in these runs.

Each directory contains `run.json`, `summary.md`, trial transcripts and model
cassettes. Requests are represented by hashes of method, URL and body; no API
keys or request headers are recorded. Compare the JSON reports with:

```sh
cd packages/overlay_eval
gleam run -m overlay/eval -- compare evidence/2026-10-04/baseline/run.json evidence/2026-10-04/explicit-execution/run.json
```

Reproduce a live run, supplying the credential through the environment:

```sh
gleam run -m overlay/eval -- validate suites/programs.eyg
OLLAMA_API_KEY=... gleam run -m overlay/eval -- run suites/programs.eyg --model ollama:gpt-oss:120b --trials 3 --timeout 60 --record evals/programs-cassettes
```

Replay the retained run without contacting a model. The replay transport
answers every request locally and needs no API key.
Strict matching rejects a changed prompt, program result or guide:

```sh
gleam run -m overlay/eval -- run suites/programs.eyg --model ollama:gpt-oss:120b --trials 3 --replay evidence/2026-10-04/explicit-execution/cassettes --out evals/replay
```

The original pure Fibonacci command also passed live on this date in 4.03 s,
returning `17710`. A separate three-trial full-session Fibonacci smoke run
passed all three, with three model calls per trial. Those smoke runs are not
included in the comparison above.
