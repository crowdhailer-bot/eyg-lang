---
name: Ordered effect tests
description: Function-valued expectations, native replies, strict ordering, and callback isolation.
---

# Ordered effect tests

Use `expect.run(program, steps)`. The program is called with `{}`; each step
receives a native request, asserts what matters, and returns a native reply.

```eyg
let {assert, expect} = import "../eyg_packages/aok/index.eyg"

let program = (_) -> {
  let _ = perform StandardOut("Loading\n")
  let bytes = assert.ok(perform ReadFile({path: "/name", offset: 0, limit: 100}))
  let name = assert.ok(!string_from_binary(bytes))
  let _ = perform StandardOut("Hello Ada")
  name
}

let value = expect.run(program, [
  expect.stdout((text) -> {
    let _ = assert.equal(text, "Loading\n")
    {}
  }),
  expect.read_file(({path, offset, limit}) -> {
    let _ = assert.equal(path, "/name")
    let _ = assert.equal(offset, 0)
    let _ = assert.equal(limit, 100)
    Ok(!string_to_binary("Ada"))
  }),
  expect.stdout((text) -> {
    let _ = assert.equal(text, "Hello Ada")
    {}
  }),
])
assert.equal(value, "Ada")
```

[`computer_effect_test.eyg`](./examples/computer_effect_test.eyg) is a complete
runnable example. The subject's file reads and output are mocked.

From the repository root, run `eyg eval guides/examples/computer_effect_test.eyg`
to obtain `Pass({})`. The [checked recording](../packages/tracing/recordings/ordered-effects.mp4)
executes this and the shared-state example. Recreate it from packages/tracing
with `EYG_BIN=/absolute/path/to/eyg gleam run -m tracing/ordered_demo`.

## Contract

- One list checks order across all registered computer effects.
- The effect kind must match before its callback runs.
- Every successful ordinary step resumes exactly once. The runner observes
  completion and any failure after the last expected operation.
- Extra operations and unconsumed expectations fail. All computer effects have
  adapters, including kinds absent from the expectation list.
- `run` returns the subject's value. Failures perform `Abort`, integrating with
  `run_test`, `run_all`, `all`, and `debug`.
- A mocked `Error(reason)` is a reply to the subject, not a test failure.
- Callback failures cannot be swallowed by the subject's own handlers.
- Callback effects use surrounding handlers and do not consume expectations.
  Nested `expect.run` calls in callbacks work independently.

Example failures: `step 2: expected ReadFile, got StandardOut`,
`step 3: missing StandardOut`, and `step 4: unexpected ReadFile`.
Callback assertion messages are preserved.

All constructors take one callback. Their names follow the computer operations:
`acquire`, `mount`, `prompt`, `read_key`, `append_file`, `create_key`, `cwd`, `decode_json`, `delete_file`, `env`, `exit`,
`eyg_parse`, `fetch`, `flip`, `hash`, `make_directory`, `now`, `random`,
`read_directory`, `read_file`, `sign`, `sleep`, `stderr`, `stdin`, `stdout`, and
`write_file`. Native request/reply shapes are in the
[CLI effect reference](./cli_effects_reference.md).

Requests are observed before host path resolution. Imports are outside the mock
boundary. Custom effects require explicit handlers or adapters.

## Terminal exit

`expect.run_exit(program, steps)` requires an `expect.exit(check)` as the final
operation and returns its status. The callback asserts on the status and returns
`{}`; this is not a fabricated reply of type `Never`. The subject's continuation
is abandoned. Missing exit, normal return, or remaining expectations fail.

## Implementation

Each descriptor contains a label and a tagged **assertion function**. The private
`AokNext` handler owns `{remaining, position}` and returns the next descriptor.
The native adapter selects its function and invokes it under [masks](./masking_effects.md):

1. Skip `AokNext`, separating the callback's effect row from the queue's type.
2. Skip every still-enclosing computer mock, so callback effects reach the test's
   surrounding handlers instead of consuming subject expectations.
3. Pass the callback's native result directly to the native resumption.

Only the expectation is tagged; replies are not wrapped or extracted. Native
resumptions stay in their adapters. The queue handler's own resumption restores
the queue scope before execution returns to the adapter.

Masking is required at runtime too: a type-only mask would route callback effects
into the wrong handler during unchecked evaluation. The interpreter and compiler
implement the same scoped routing.

## Verification

`expect_test.eyg` covers each registered effect, callback routing, ordering,
completion, assertion isolation, nested runners, and terminal exit. A CLI test
compares adapters against the actual computer registry. Run `eyg script entry.eyg`
from the repository root.

A finite expectation list bounds accepted interactions, not computation between
them.
