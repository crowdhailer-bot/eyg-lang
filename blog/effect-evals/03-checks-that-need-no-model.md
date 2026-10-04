---
name: Checks that need no model
description: Grading values, packages, effects and files, and proving a task measures the task.
---

# Checks that need no model

A check should be the cheapest thing that can tell you whether the work was
done. For an agent that writes programs, that is usually not a model.

## Tasks are EYG records

A suite is an EYG module whose fields are tasks. Each task is a record:

```eyg
{
  description: "Find the json package and decode a nested field of an API response.",
  tags: ["libraries"],
  prompts: ["An API returned this JSON: {\"user\": {\"name\": \"Ada\", \"id\": 7}}. Run a program that works out the user's id."],
  checks: [Computes(7), References("json")],
  reference: [[Run("..."), Say("The user's id is 7.")]]
}
```

Writing tasks in EYG rather than JSON or Gleam has one large advantage:
expected values are ordinary EYG values, of whatever type the task needs, and a
check can be an EYG function. A record of tasks, rather than a list, is what
lets one task expect `7` and the next expect `{name: "Ada"}`.

## Five kinds of evidence

**The value.** `Computes(7)` compares EYG values structurally. When the exact
value is too strict, `Satisfies` runs an EYG predicate over it:

```eyg
Satisfies({
  description: "is a GET request to api.github.com/users/crowdhailer",
  check: (request) -> { !equal(request.host, "api.github.com") }
})
```

**What the program used.** `References("json")` parses the program the agent
ran and looks for the package in its syntax tree. It does not care whether the
agent found the package by searching a catalogue, by reading a guide or by
knowing it already, which is right: the task is "use the library that exists",
not "use it the way I imagined".

`ReadsContext(["libraries", "search"])` is the same idea for the context a
session was given: it finds `context.libraries.search` however it was written.

**The effects.** `Fetches("/guides/cli-effects-reference")` passes when a
program fetched that URL and got an answer. Overlay's own module loading is
recorded separately, so a check about the agent's behaviour is never satisfied
by the runtime's own traffic.

**The state left behind.** `FileContains`, `NoFile`, and for notes an agent
names itself, `AnyFileContains({directory: "notes", text: "@json"})`.
`WorkspaceUnchanged({})` is the check for a request that needed no files at
all, and it catches the agent that helpfully leaves a note about nothing.

`FileSatisfies` goes further: it loads a module the agent left in the
workspace, resolving its imports, and applies a predicate to its value.

```eyg
FileSatisfies({
  path: "src/greet.eyg",
  description: "greets Ada with \"Hello, Ada\"",
  check: (greet) -> { !equal(greet("Ada"), "Hello, Ada") }
})
```

The agent fixed a typo in a different file, `src/words.eyg`, and this still
passes, because it asks what the code does rather than how it looks.

**What was said.** `Says("pull request")` and `NeverSays("pull request")` for
the few cases where particular words matter.

## Prove the task before trusting it

Two agents, neither needing a model, decide whether a task is worth running.

The **oracle** follows the task's reference solution. It must pass every
deterministic check. If it does not, either the task cannot be done in this
environment, or a check is wrong. Both are worth knowing before a model is
blamed for failing.

The **null agent** replies "I can't help with that" and runs nothing. It must
fail. If it passes, the task rewards doing nothing: usually a check that is
true of an untouched workspace, or a `NeverSays` with no partner check.

```sh
gleam run -m overlay/eval -- validate suites/contexts.eyg
```

This runs in CI on every change. It is the cheapest eval in the suite and the
one that keeps the others honest.

## A worked failure

The first run of a task about replacing text in a file failed for the oracle,
with:

```
Ran:
@edit.replace_all({path: "docs/README.md", find: "Overlay App", replace: "Overlay"})
Result: type errors
missing reference @edit
```

The package had been fetched, so the message looked wrong. It was not: modules
on a hub must pin the packages they use to a release, and the fixture was
serving `@edit` with a bare reference to `@standard` inside it, which the
module cache refuses to resolve. `eyg share` pins as it publishes; the fixture
now does the same.

That is a harness bug found by a task validity check, before any model saw it.
Which is the point.
