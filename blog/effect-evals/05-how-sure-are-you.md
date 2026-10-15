---
name: How sure are you?
description: Trials, pass@k, pass^k and error bars that survive scrutiny.
---

# How sure are you?

A single number from a single run of sixteen tasks is not a measurement, it is
an anecdote. Three things make it one: repeat the trials, report the right
statistic, and pair comparisons.

## Repeat the trials

Models are not deterministic, and an agent that solves a task four times out of
five is a different product from one that solves it once out of five, even
though both "pass". So each task is run several times, and the report keeps two
numbers.

**pass@k** is the chance that at least one of k trials passes. It is the right
measure when a person can look at the answer and try again: a tool where any
working result is enough.

**pass^k** is the chance that all k pass. It is the right measure for anything
someone depends on without checking. It falls fast, and that fall is the honest
picture. An agent passing 80% of trials has a pass^5 of about 33%: run it five
times and it will probably let you down once.

Both are estimated without bias from the trials actually run, rather than by
taking the observed rate to the power of k.

## Error bars, clustered by task

Evaluation scores are means over a sample of tasks, so they have a standard
error, and it belongs next to the score:

```
Pass rate **62%** (95% CI 45%–79%) over 16 tasks, mean score 81%.
```

The subtlety is that trials are not independent samples. Five trials of one
task tell you much less than five trials of five tasks: a task that is
impossible in your environment fails five times for one reason. Treating every
trial as a sample makes the interval too narrow, and that is how a suite
convinces its owner that noise is progress. Compute the error from per task
means instead, which is what clustering by task amounts to.

## Pair your comparisons

Most decisions are comparisons: this context or none, this model or that one,
the prompt before or after a change. Comparing two independent intervals wastes
most of the information, because the biggest source of variation is which tasks
are in the suite, and both runs have the same tasks.

Pair by task and report the difference:

```
A minus B is **+19pp** (95% CI +6pp to +32pp) over 16 paired tasks, a significant difference.

| Task | A | B | A − B |
| --- | --- | --- | --- |
| json_nested_field | 100% | 60% | +40pp |
| leave_workspace | 80% | 80% | 0pp |
```

Task by task differences are also where the interesting reading is: a change
that lifts six tasks and sinks two is a different thing from one that lifts
everything a little.

## Watch for saturation

When a suite is passed every time, it has stopped measuring capability and
started protecting it. That is a promotion, not a failure: keep those tasks as
regressions, run them on every change, and write new tasks for what the agent
still cannot do. A suite that never changes is measuring the past.

## Read the transcripts anyway

Numbers say how much passed, transcripts say why. Read the failures, and read a
few passes: a check that passes for the wrong reason is worse than one that
fails, because nobody looks at it again. Every trial is written out next to the
summary for exactly this.
