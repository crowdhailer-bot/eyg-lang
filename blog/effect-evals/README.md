---
name: Effect evals
description: A series on evaluating agents that write EYG programs, where every effect is explicit.
---

# Effect evals

Overlay answers people by writing EYG programs and running them. EYG has
managed effects: a program cannot touch the world except by performing an
effect the runtime hands back. That one property changes what an eval can be.

This series is about evaluating such agents, and the contexts they work in.

These articles retain the source branch's design discussion. Reported live
model results are historical evidence, not new model calls during consolidation.
The current [eval guide](../../guides/overlay_evals.md) and
[sandbox guide](../../guides/sandbox.md) describe today's bounded runtime.

For a technical talk, open [Make agent changes measurable](./slides.html)
or its [PDF copy](./slides.pdf). The deck has 32 main slides and six reference
slides, with speaker notes for a roughly 40–45 minute presentation. It covers
the pure live eval, architecture and component implementations, context tasks,
grading, experimental design, and sandbox boundaries. Examples distinguish
recorded results from proposed experiments and hardening.

The talk describes the historical 441d4e2 design snapshot of 26 September 2026;
its remaining-hardening claims are not a list of current gaps. The editable
source is slides.template.html; its controller is
[Gleam](../../packages/tracing/src/tracing/eval_slides.gleam).
From packages/tracing, run gleam run -m tracing/build_slides after edits.
The generated HTML works offline without dependencies. Use
the arrow keys or Space to navigate, **N** for notes, **F** for fullscreen,
and the slide selector to jump. The reliability slide has interactive controls;
its numbers are illustrative. Use **P** or **Print / PDF** to export all slides
in landscape 16:9, with background graphics enabled and browser headers/footers
disabled. Speaker notes remain in the HTML. Regenerate `slides.pdf` after edits.

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

The [live execution comparison](07-making-overlay-execution-reliable.md) shows
how the runner changed the production prompt, including a rejected experiment.

The [presentation guide](../../guides/eval_presentations.md) includes the checked
video and commands for rebuilding the HTML and PDF with Gleam tooling.
