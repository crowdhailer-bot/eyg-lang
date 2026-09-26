---
name: Effect evals
description: A series on evaluating agents that write EYG programs, where every effect is explicit.
---

# Effect evals

Overlay answers people by writing EYG programs and running them. EYG has
managed effects: a program cannot touch the world except by performing an
effect the runtime hands back. That one property changes what an eval can be.

This series is about evaluating such agents, and the contexts they work in.

For a runnable starting point, begin with the [pure Fibonacci eval](../../packages/overlay_eval/README.md).
It makes one real model request and checks the value of a program with no effects.
The articles below describe the subsequent session, fixture and grading layers.

1. [Effects make evals honest](./01-effects-make-evals-honest.md) — why an
   agent that writes managed-effect programs can be measured by what it did,
   not by what it said it did.
2. [A session under eval](./02-a-session-under-eval.md) — running the real
   agent against fixtures by performing its effects yourself.
3. [Checks that need no model](./03-checks-that-need-no-model.md) — grading
   values, packages, effects and files, and proving a task measures the task.
4. [A judge for the rest](./04-a-judge-for-the-rest.md) — model graded checks
   that stay trustworthy.
5. [How sure are you?](./05-how-sure-are-you.md) — trials, pass@k, pass^k and
   error bars that survive scrutiny.
6. [Evaluating a context](./06-evaluating-a-context.md) — what a context is for,
   and how to find out whether yours earns its tokens.

The code is in [`packages/overlay_eval`](../../packages/overlay_eval/README.md)
and the practical summary is the guide
[Evaluating Overlay agents](../../guides/overlay_evals.md).
