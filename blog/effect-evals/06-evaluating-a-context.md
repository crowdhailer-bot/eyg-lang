---
name: Evaluating a context
description: What a context is for, and how to find out whether yours earns its tokens.
---

# Evaluating a context

An Overlay session is given a context: an EYG module whose readme becomes part
of the system prompt and whose fields are in scope for every program the agent
writes. It is the closest thing Overlay has to a repository's `AGENTS.md`, with
one difference: it is code, so it can do things.

```eyg
{
  readme: "...",
  libraries: {all: catalogue, search: (query) -> { ... }},
  guides: {all: index, search: (query) -> { ... }, read: (slug) -> { ... }},
  source: {map: files, read: (path) -> { ... }, list: (path) -> { ... }},
  workspace: {notes: (_) -> { ... }, write_note: (note) -> { ... }}
}
```

Two contexts live in `eyg_packages`. **overlay_librarian** catalogues the
packages and the guides and searches them, so an agent can find what exists
before writing code. **overlay_maintainer** adds Overlay's own source: a map of
the files that explain how it behaves, reading them from GitHub, notes kept in
a workspace, and a readme that says when to suggest a pull request and when to
just fix the program.

## Contexts are not free

Every request carries the readme, and every extra instruction competes with the
task in front of the model. Studies of repository context files have found
generated ones making agents slightly worse while costing over 20% more tokens,
and carefully written ones helping by a few points. A context that has not been
measured is a guess with a running cost.

So measure it. The same suite, with and without:

```sh
gleam run -m overlay/eval -- run suites/contexts.eyg \
  --context none \
  --context ../../eyg_packages/overlay_librarian/index.eyg \
  --context ../../eyg_packages/overlay_maintainer/index.eyg \
  --model ollama:gpt-oss:120b --trials 5
```

Each run writes a report, and each later context is compared against the first,
paired by task.

## What the tasks look for

Sixteen tasks, tagged by what they are about.

**Finding libraries.** Decode a nested field of an API response; encode a
record as JSON; build an HTTP request without sending it; replace text in a
file. The checks are the value computed and `References("json")`,
`References("http")`, `References("edit")`. A context that catalogues packages
should show up here.

**Searching guides.** How to read part of a file with the CLI; how to let a
script fetch but not write. The checks are the guide fetched and a judged
criterion about the answer.

**Its own source, and pull requests.** Overlay has no `Sleep` effect: the
harness that lists the effects programs can perform has it commented out. Asked
to wait a second, the right behaviour is to find that, say so, and suggest a
pull request. The balancing tasks are a program with a plain mistake in it and
a broken link to a guide, where suggesting a pull request is exactly wrong.
`pull-request` and `no-pull-request` are separate tags, so the report shows both
sides rather than one number that can be gamed by always suggesting, or never.

**A workspace and its notes.** Fix a typo in a project so its code behaves;
write a note about something learnt, with frontmatter, and not a note about
nothing; correct a note that is wrong; leave a workspace alone when the request
did not need it.

Every one of those has a reference solution that works with any context, so the
tasks measure what the agent achieved and not how a particular context expected
it to get there. A context cannot pass a task by being the only way to do it.

## Keeping a context honest

A catalogue rots. Tests in the repository check that every package the
librarian lists is published, that every guide on the site is in its index and
every slug in its index is on the site, and that every path on the maintainer's
source map still exists. Writing the guide that goes with this series added a
guide to the site, and the index test failed the same minute, which is how it
should be.

Those are not evals, they are unit tests, and that is the point: check what
code can check, and spend the eval on whether an agent given the context
actually does better work.
