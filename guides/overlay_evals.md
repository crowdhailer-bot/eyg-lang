---
name: Evaluating Overlay agents
description: How to write and run evals for Overlay agents and the contexts they work in.
---

# Evaluating Overlay agents

Overlay answers people by writing EYG programs and running them. Two things
make it unusually easy to measure. A program returns a value, so a check can
compare what the agent worked out rather than what it said about it. Every
effect is explicit and managed, so a session can be run against fixtures
instead of the world, and every effect it performed is in the record.

The tools are in [`packages/overlay_eval`](../packages/overlay_eval/README.md),
which has the reference for tasks, checks and the command line. This guide is
about what to measure and how to keep the measurements honest.

## The words

- A **task** is one case: what the person asks, what the session starts with,
  and how a good outcome is recognised.
- A **trial** is one attempt at a task. Models are not deterministic, so a task
  is run several times.
- A **check** grades a trial. Deterministic checks read the values, effects and
  files of the run; judged checks ask a model one question about it.
- A **transcript** is the record of a trial: turns, programs with the value each
  computed, effects that reached the environment and the workspace left behind.
- An **environment** is what the session can reach: a hub of packages, the
  guides, a repository, and fixed answers for other services.
- A **suite** is a set of tasks, written as one EYG module.

## Start from something that went wrong

The best first tasks are failures you have seen: a question the agent answered
from memory instead of running a program, a library it wrote out by hand, a
guide it never read. Twenty of those are worth more than a hundred invented
ones. Write the task, then write a reference solution for it. If you cannot
write the solution, the task is not ready.

## Grade what was achieved

Grade the outcome, not the path. An agent will find ways you did not think of,
and a check on the sequence of tool calls punishes it for that.

Prefer, in this order:

1. **The value a program computed.** `Computes(7)` compares EYG values, and
   `Satisfies` runs an EYG predicate over the value for anything looser.
2. **What the program used.** `References("json")` reads the program's syntax
   tree, so it sees the package however the agent found it.
3. **The effects that happened.** `Fetches("/guides/json")` says a guide was
   read; the effect log is the truth about what left the session.
4. **The state left behind.** `FileContains`, `FileSatisfies` for a workspace
   module's value, `WorkspaceUnchanged` when a request needed no files.
5. **What was said.** `Says` and `NeverSays` for words that must or must not
   appear, such as a suggestion to open a pull request.
6. **A judge**, for what none of the above can decide.

## Use a judge carefully, and only where it earns its place

A judge decides one criterion at a time, in words, with a verdict of pass, fail
or unknown, and reasons before it answers. Give it a way out: a judge forced to
choose on a transcript that cannot settle the question will invent a reason.

Use a model from a different family to the agent under eval, since judges
prefer their own family's writing, and never judge what a value already proves.
Before trusting a judge, grade thirty trials yourself and compare: count how
often it agrees with you on the ones you passed and on the ones you failed,
separately. Raw agreement hides the imbalance.

## Balance the set

For every behaviour that should happen, write the case where it should not.
Suggesting a pull request when Overlay is at fault is only useful if the agent
does not suggest one when the mistake is in its own program. The suite has both
under the tags `pull-request` and `no-pull-request`, and reports each tag
separately.

## Prove the task measures the task

Two agents check a task before any model runs:

- the **oracle** follows the reference solution and must pass every
  deterministic check,
- the **null agent** replies without running anything and must fail.

If the oracle fails, the task is unsolvable or a check is wrong. If the null
agent passes, the task can be passed without doing the work. Both run in CI,
and neither needs a model.

## Say how sure you are

Run several trials of each task. Report `pass@k`, the chance at least one of k
trials passes, when any working answer is enough, and `pass^k`, the chance all k
pass, when a person depends on it every time. `pass^k` falls quickly, and that
fall is the honest picture of an agent's reliability.

Trials of one task are not independent, so compute the error from per task
means rather than from every trial, and report a 95% interval with the score.
When comparing two runs, pair them by task: the difference between contexts on
the same tasks is measured far more precisely than each score alone.

## Evaluating a context

A context is the module an Overlay session is given: its readme becomes part of
the system prompt and its fields are in scope for every program. A good context
should make an agent find the right library, read the right guide, know where
its own source is, and keep a workspace tidy.

Measure that by running the same suite with and without it:

```sh
# packages/overlay_eval
gleam run -m overlay/eval -- run suites/contexts.eyg \
  --context none --context ../../eyg_packages/overlay_librarian/index.eyg \
  --model ollama:gpt-oss:120b --trials 5
```

The comparison is paired by task and reports the difference with an interval.
Context files are not free: they cost tokens on every request, and studies of
repository context files have found that a poor one can make an agent worse.
Expect a context to earn its place, and keep the tasks that show where it does.

## Read the transcripts

Reports say how much passed, transcripts say why. Read them for the tasks that
failed, and for a few that passed: a check that passes for the wrong reason is
worse than one that fails. Every trial is written out as markdown next to the
summary.

## Keep them running

Record the model's side of a run into cassettes and replay it to grade a run
again, or to check a change to the harness, without calling a model. A replayed
request that no longer matches means the session changed, usually the prompt or
a context, and the recording needs making again.

Once a capability passes reliably, its tasks stop measuring progress and start
protecting it. Keep them, run them on changes, and write new tasks for what the
agent cannot do yet.

## Where this comes from

The vocabulary and much of the advice follow Anthropic's
[Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents),
the validity checks follow the
[Agentic Benchmark Checklist](https://arxiv.org/abs/2507.02825), the statistics
follow [Adding Error Bars to Evals](https://arxiv.org/abs/2411.00640), and the
`pass@k` estimator is from the
[Codex paper](https://arxiv.org/abs/2107.03374). `pass^k` as a measure of
reliability comes from [τ-bench](https://arxiv.org/abs/2406.12045). The
judge practice follows Hamel Husain and Shreya Shankar's
[evals FAQ](https://hamel.dev/blog/posts/evals-faq/). On whether context files
help, see
[Evaluating AGENTS.md](https://arxiv.org/abs/2602.11988) and
[Probe-and-Refine Tuning of Repository Guidance](https://arxiv.org/abs/2606.20512).
