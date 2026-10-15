---
name: Writing tests with aok
description: Write value assertions and ordered computer-effect tests using aok.
---

## Writing a test

A test is a record with `name` and `test` fields. `test` is called with `{}`
and performs `Abort` on failure. Return `{}` for a consistently typed test list.

```eyg
let {assert, expect} = import "../eyg_packages/aok/index.eyg"

[
  {name: "addition", test: (_) -> {
    let _ = assert.equal(!int_add(1, 1), 2)
    {}
  }},
  {name: "greeting", test: (_) -> {
    expect.run((_) -> {
      perform StandardOut("Hello, Bill")
    }, [expect.stdout((message) -> {
      let _ = assert.equal(message, "Hello, Bill")
      {}
    })])
  }},
]
```

## Testing effects

`expect.run(program, steps)` checks a single ordered list of interactions and
returns the program's value. Each expectation takes a callback from the lifted
request to the reply supplied when resuming. Callback assertions fail through
`Abort`. Wrong kinds, missing/extra operations, and failure after the final
operation all fail the test.

All 26 computer effects from the subject are mocked, including operations not
mentioned in the list: those are rejected instead of reaching the platform.
Callbacks can use the surrounding runtime's effects without consuming steps.
`expect.run_exit` checks the subject's terminal `Exit` without exiting the test
process or resuming the subject.

See [Testing ordered computer effects with aok](./ordered_effect_tests.md)
for the API, complete examples, exit tests, and how masking isolates callbacks.

## Running tests

- `run_test(test)` returns `Pass({})` or `Fail(reason)`.
- `run_all(tests)` returns a list of `{name, outcome}` records.
- `all(tests)` prints the report and returns `{passed, failed}`.
- `debug(tests, name)` calls the named test without catching `Abort`, so the
  CLI can report its source-located stack trace.

To test that a computation aborts, call `run_test` and assert that its outcome
is `Fail` with the expected reason. A normally returned `Fail(...)` value by
itself is not a failure to the outer test runner; use an assertion on it.

Expose package tests through `entry.eyg`'s `tests` field and include them in
the repository-level suite:

```sh
eyg script entry.eyg
```
