---
name: Evaluating Overlay contexts
description: Why the eval runner performs Overlay's own effects, and the trade-offs taken in its suite.
date: 2026-09-17
---

[`packages/overlay_eval`](../packages/overlay_eval/) evaluates Overlay agents and
the contexts they are given. The choices worth recording are the ones that are
not visible in the code.

## The runner performs the product's effects

A session under eval is `overlay/web/state.update`, the state machine the browser
runs. Overlay returns its input and output as `pal/system` effect values, so the
runner interprets them against fixtures: a hub serving `eyg_packages`, the
guides directory as eyg.run, and this repository as it appears on GitHub. The
alternative, a small agent loop written for the eval, is easier to start and
diverges from the product within a week. Each change to the system prompt is a
change the eval sees.

The model is a fixed point of the same idea: completions arrive through
`FetchStreamResponse`, so a provider, a recorded cassette and a scripted agent
are interchangeable, and a suite can be replayed and graded again without a
model.

## Trade-offs taken

- **Tasks are EYG records, not JSON or Gleam.** Expected values are then
  ordinary EYG values of whatever type a task needs, and a check can be an EYG
  predicate. A record of tasks rather than a list is what lets one task expect
  `7` and the next expect `{name: "Ada"}`.
- **Trials run one at a time.** Sequential trials keep a run readable as it
  happens, keep provider rate limits out of the results, and cost nothing worth
  having: a run's time is dominated by the model. Trials share no state, so
  running them in parallel is possible later.
- **Fixtures pin package references.** Modules published to a hub must pin the
  packages they use to a release, or the module cache refuses to resolve them.
  The first fixture served a bare reference and the oracle failed with
  `missing reference @edit`, which looked like a missing package and was a
  missing pin. `hub.publish_directory` now pins in dependency order, as
  `eyg share` does.
- **Judged checks are one criterion each.** A judge asked for a score returns a
  number that means nothing twice. `calibrate` exists because a judge with no
  measured agreement is a decoration, and it hides its own verdicts from the
  person grading so that the labels stay independent.
- **The browser harness has nondeterministic effects.** `Now` and `Random` are
  available to programs an agent writes, and a task that depends on either
  cannot have a stable expected value. Such a task needs `Satisfies` with a
  predicate over the value, not `Computes`.

## What is checked by tests instead of evals

The freshness of a context is a unit test, not an eval: every package the
librarian lists is published, every guide on the site is in its index and every
slug in its index is on the site, and every path on the maintainer's source map
exists. Spend the eval on whether an agent given the context does better work.
