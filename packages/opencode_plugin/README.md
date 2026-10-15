# Shared harness policy runtime

This Gleam runtime executes EYG with per-effect gates, captured output and
host callbacks. It is shared by the harness integrations. The native dispatcher
adapter wraps OpenCode v1.19.0's own tools and MCP pipeline, including Task's
child-session notification. Configuration is trusted EYG.

```sh
bun install
gleam run -m build
gleam test
gleam test --runtime node
```

Build before testing: the native host check imports the actual dist/core.mjs.
The two-line native entry only re-exports the Gleam API and list conversion.
The [guide](../../guides/harness_policies.md) explains policy chains, imports,
absolute paths, host callbacks and cache ownership.
The [OpenCode dispatcher guide](../../guides/opencode_dispatcher.md) covers the
pinned installer, only/gate/off modes and the checked upstream recording.
`gleam run -m upstream_check` runs the real patched upstream function with
deterministic services and official SDK packages, without a model call.
