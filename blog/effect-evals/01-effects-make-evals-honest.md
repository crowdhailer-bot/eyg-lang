---
name: Effects make evals honest
description: Why an agent that writes managed-effect programs can be measured by what it did.
---

# Effects make evals honest

Most evals of agents have the same weakness: the thing being graded is a
conversation. An agent says it fetched the page, says it fixed the file, says
the answer is 7. Graders then read that conversation and try to decide what
really happened, usually with another model.

Overlay is in a better position, for two reasons.

## A program returns a value

Overlay does not answer questions directly, it writes an EYG program and runs
it. Asked for the id in a response body, a capable session runs something like

```eyg
let {decode: d, parse} = @json
match parse(body, d.object(d.field("id", d.integer))) {
  Ok(id) -> { id }
  Error(reason) -> { !never(perform Abort(reason)) }
}
```

and the tool result is the value `7`, not the sentence "the id is 7". A check
can compare EYG values:

```eyg
checks: [Computes(7)]
```

That check has no prompt, no judge and no ambiguity. If the agent talked its
way to the right sentence without computing it, the check fails, which is
exactly what we want to know.

## Every effect is explicit

EYG programs cannot read a file, fetch a page or write anything without
performing an effect, and the runtime decides what performing it means. Overlay
is written the same way: its state machine returns its input and output as
values describing work to be done, which the browser performs.

So an eval does not have to trust a network, and does not have to mock at the
level of a function. It performs the effects itself:

- a hub serving the repository's packages, so `@json` resolves to the version
  in this checkout,
- the guides of eyg.run served from the `guides` directory,
- the repository itself served as it appears on GitHub, so an agent can read
  its own source without leaving the machine,
- an in-memory file system for sessions that have a workspace,
- anything else refused, and recorded as refused.

A session under eval is then hermetic and repeatable, and every effect it
performed is in the record:

```
- GET https://eyg.run/guides/cli-effects-reference.md 200
- GET https://raw.githubusercontent.com/CrowdHailer/eyg-lang/main/packages/touch_grass/src/touch_grass/harness/browser.gleam 200
- GET https://example.com/ failed: the eval environment has no network access to example.com/
```

"Did it read the guide before answering?" stops being a question for a judge.

## What is left for judgement

Plenty. Whether an explanation is right, whether a note is concise and worth
keeping, whether a suggested change to Overlay makes sense: those need a
reader. The point is not to remove judgement, it is to spend it where it is
needed, on the part of the work that cannot be checked by comparing a value.

The rest of this series builds that out: a runner that performs the agent's
effects, checks that need no model, a judge for what is left, and the
statistics to say how sure you are.
