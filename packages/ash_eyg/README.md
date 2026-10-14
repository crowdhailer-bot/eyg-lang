# EYG in Ash

Expose Ash resource actions as typed effects. The resource/domain DSL and Ash
calls are native Elixir bridges; signatures, values, script execution, package
loading and Mix command behavior are implemented in Gleam.

Add this local dependency, then `AshEyg.Domain` and `AshEyg.Resource` to the
domains and resources available to scripts:

```elixir
{:ash_eyg, path: "path/to/eyg-lang/packages/ash_eyg"}
```

`AshEyg.effects(domains: [Your.Domain])` derives a list that the host can restrict.
`AshEyg.check(source, cache, effects: effects)` and `run/3` return `{result, cache}`.
`AshEyg.Session` serializes calls and retains that cache in a supervised process.
Actor, tenant and context options are passed to the Ash action calls.
`AshEyg.RunScript` adapts a generic action with a `source` argument.

The [Ash guide](../../guides/embedding_ash.md) covers action types, optional
inputs, scoping, cache ownership and the checked [helpdesk](../../examples/helpdesk).
Mix commands are `ash_eyg.effects`, `ash_eyg.check` and `ash_eyg.run`; the latter
two accept a script path or `-e source`.

```sh
mix deps.get
mix test
```

The ExUnit hooks invoke eight Gleam integration checks for discovery, renamed
and hidden resources, public fields, CRUD/generic actions, actor/tenant/context,
scope rejection before effects, custom effects, package reuse/rollback,
independent sessions, generic-action errors and conversions. Gleam and a
compatible Elixir/OTP pair are required to build the local libraries.
