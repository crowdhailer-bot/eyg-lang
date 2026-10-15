# Shared harness policy runtime

This Gleam runtime executes EYG with per-effect gates, captured output and
host callbacks. It is shared by the harness integrations. Configuration is
trusted EYG; agent code runs under its policy with context in scope.

```sh
gleam run -m build
gleam test
gleam test --runtime node
```

Build before testing: the native host check imports the actual dist/core.mjs.
The two-line native entry only re-exports the Gleam API and list conversion.
The [guide](../../guides/harness_policies.md) explains policy chains, imports,
absolute paths, host callbacks and cache ownership.
