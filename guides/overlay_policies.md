---
name: Overlay policies
description: Allow, mock or refuse effects in an overlay agent.
---

# Overlay policies

An overlay configuration has a `context` and a `policy`. A policy contains one
function per allowed effect. A missing field refuses that effect; `{}` refuses
all effects. The runtime checks the policy before performing an effect.

Allow Fetch while denying file writes:

```eyg
{
  context: {},
  policy: {fetch: (request) -> { Pass(request) }}
}
```

`Pass(input)` performs the effect. `Mock(result)` returns a value without
performing it. For example, a `write_file` function returning
`Mock(Error("read-only session"))` lets the program handle that refusal as a
normal file error. An omitted field instead stops that program.

The CLI checks effect types against its runtime. A browser session exposes its
own effects, including Artifact, Show and Puppet. File effects are only available
in a session with a workspace. Policies apply to those effects too.

See the [overlay package](../eyg_packages/overlay/README.md) for path restrictions,
Ask decisions, audit callbacks and reusable helpers. The old `overlay.access`
wrapper has been replaced by runtime policies.
