---
name: Policies for embedded harnesses
description: Gate computer and host effects with composable EYG functions.
---

# Policies for embedded harnesses

[opencode_plugin](../packages/opencode_plugin/) provides the shared Gleam
runtime. A trusted configuration returns policy, optional context and optional
named agent policies. Agent code gets context in scope; each run starts fresh.

```eyg
{
  policy: {
    read_file: Pass,
    write_file: (_) -> { Mock(Error("read only")) }
  },
  context: {readme: "Inspect files and propose changes."}
}
```

Each field is an effect's snake case name: ReadFile uses read_file and Task
uses task. Pass(lift) continues with that request; Mock(lower) resumes with a
reply without calling the host. A missing gate makes the effect unavailable.
DecodeJSON, EYGParse, Flip, Hash and Random are available without gates.
StandardOut and StandardError are captured unless explicitly gated. Exit is
unavailable; StandardIn has no input in this host.

Gates are pure functions. Resolve any imported helpers while loading the
trusted configuration. A gate cannot perform effects or load new references.
The configuration itself executes as trusted host code and may use IO.

`restrict(parent, child)` retains only fields present in both. For a request,
the child gate runs first, followed by the parent gates. Rewritten file paths
are normalized to absolute paths before each gate. A Mock ends the chain,
since it performs no host operation. A named agent's configured policy can
serve as its starting policy; adapters choose when explicit escalation is allowed.

Relative program imports use the read_file gate for every file, including
nested imports. A rewritten module path anchors further imports to its new
location. Module loading is pure; functions it defines may perform effects
later under the caller's policy. File policies compare normalized paths;
filesystem confinement uses the separate [sandbox](./sandbox.md).

Host effects use `host(label, request_description, reply_description, callback)`.
The same gates run before their callbacks. Requests cross as native objects,
arrays and booleans; Some unwraps, None becomes null, and other tags become
single-field objects. The callback also receives the raw EYG value, allowing
Task to retain policy functions. Replies resume as Ok(value), and thrown or
rejected callbacks resume as Error(message). These host type descriptions are
for the model; runtime conversion and the host's own validation check arguments.

`run(code, policy, context, directory, hosts)` returns a report containing
success, output, final value and observed effect labels. The explicit directory
anchors file operations. Hub package loading owns a separate cache inside each
run, as in the other embedding APIs; retaining configuration retains its loaded
helpers and values. The standalone core includes no opencode or pi SDK.

From packages/opencode_plugin, run `gleam run -m build`, then `gleam test` and
`gleam test --runtime node`. The checks cover actual file reads, mocked writes,
denial, child restrictions, normalized rewrites, nested imports, pure gates,
host failures and a native consumer of the built dist/core.mjs.
