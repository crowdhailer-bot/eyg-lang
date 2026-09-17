---
name: Hex rate limits in CI
description: Why matrix jobs fail at "Resolving versions" with no change to the package.
date: 2026-09-17
---

Jobs in the `test-bun` and `test-beam` matrices fail from time to time with:

```
  Resolving versions
error: Hex API failure
    The rate limit for the Hex API has been exceeded
```

Which packages fail varies between runs, and packages nobody touched fail
alongside the one that changed. It is not a test failure: the step that fails is
whichever `gleam` invocation resolved versions when the limit was reached.

Every `gleam build` and `gleam test` in a package with path dependencies
resolves versions again, because a path dependency's own requirements can change
without a version to pin them. `packages/overlay_eval`, `gleam_cli`, `website`,
`pal`, `morph` and `gleam_hub` all have them, so each of their jobs makes
several Hex API calls, and all of the matrix jobs share one runner's address.

Gleam's own help for `build` names the remedy:

> This command optionally accepts the environment variable
> `HEXPM_READ_API_KEY`, which can hold a Hex API key to authenticate with Hex
> with a higher rate limit.

That needs a repository secret, so it is a decision for the repository owner.
Staggering the matrix with `max-parallel`, or retrying the deps step, would
lower the rate rather than raise the limit.

Reading which step failed needs no sign in, but the logs do. The workflow can be
made to say why in an annotation, which is readable, by capturing the output of
a step and echoing its tail as `::error::` when the command fails.
