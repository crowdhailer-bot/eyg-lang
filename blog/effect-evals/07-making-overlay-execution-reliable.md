---
name: Making Overlay execution reliable
description: Real evals reveal the difference between saying an answer and returning it from a program.
date: 2026-10-04
---

# Making Overlay execution reliable

Ask an agent to run a program, and you should be able to inspect what it ran.
Overlay now has an evaluation runner that checks that promise against the same
session engine used in the browser. It records the programs, the values they
returned, the effects they requested and the files they left behind.

That immediately found something useful. On four small programming tasks,
Ollama's `gpt-oss:120b` passed seven of twelve trials. Several programs printed
the requested answer but returned an empty record. Other responses needed
multiple attempts to find valid syntax. A plausible final reply could hide both.

## A clearer contract for running code

The updated instructions tell the agent to execute when asked, leave the requested
value as the final expression and consult the syntax guide after a syntax error.
The tool description now explains why Print is different: it adds output and
returns `{}`. The final expression is the program's result.

With the same model, tasks and checks, the revised prompt passed eleven of twelve
trials. It used 51 model calls compared with 49 before. This is a useful improvement
in completing these tasks, not a claim that every interaction is faster. One
record-update trial still answered without executing. Four tasks are a starting
point for finding problems, not enough to promise a universal success rate.

We also tried replacing the syntax-guide step with a compact reference. That
passed only five trials. Keeping the failed experiment alongside the successful
one makes the decision inspectable.

## Try a change and keep the evidence

The runner supports real model sessions, isolated workspaces, local package and
guide fixtures, deterministic checks, optional judges, repeated trials and replay.
Before spending a model call, it verifies that a reference solution passes each
task and an agent that does nothing fails it.

```sh
cd packages/overlay_eval
gleam run -m overlay/eval -- validate suites/programs.eyg
OLLAMA_API_KEY=... gleam run -m overlay/eval -- run suites/programs.eyg --model ollama:gpt-oss:120b --trials 3
```

The [full comparison and recordings](../../packages/overlay_eval/evidence/2026-10-04/README.md)
include all three experiments, their limitations and commands for replaying them.
Use the [eval guide](../../guides/overlay_evals.md) to add a task that matters to
your own workflow. A change to an agent is much easier to trust when you can
inspect the program that made the result true.
