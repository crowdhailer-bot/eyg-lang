---
name: Embedding EYG in Ash
description: Derive typed effects from Ash resource actions, restrict script capabilities and retain validated packages in a supervised session.
---

# Embedding EYG in Ash

[Watch the checked AshAdmin walkthrough](/glasshouse/ash-helpdesk.webm).

The [helpdesk example](../examples/helpdesk/) exposes Ash actions to EYG and runs
scripts through AshAdmin. Gleam owns execution, package loading, conversions,
scope selection, browser highlighting and tooling. Elixir supplies Ash metadata,
action calls, OTP callbacks and framework templates.

## Expose and restrict actions

Add the local `ash_eyg` dependency to `mix.exs`:

```elixir
{:ash_eyg, path: "../../packages/ash_eyg"}
```

Use `AshEyg.Domain` on the domain and `AshEyg.Resource` on exposed resources:

```elixir
use Ash.Domain, extensions: [AshEyg.Domain]
use Ash.Resource, domain: Helpdesk.Support, extensions: [AshEyg.Resource]
```

Labels combine domain, resource and action names: `SupportTicketOpen`.
The `eyg` DSL can override the domain/resource name or set `expose? false`.
Only public attributes and primary keys appear in returned records.

| Ash action | Input | Successful reply |
| --- | --- | --- |
| read | arguments | list of records |
| create | accepted attributes and arguments | record |
| update | primary key, accepted attributes and arguments | record |
| destroy | primary key and arguments | `{}` |
| generic action | arguments | declared return type or `{}` |

Replies are `Ok(value)` or `Error(String)`. Optional inputs use `Some(value)` or
`None({})`; `None` omits the input so Ash defaults apply. Integers, booleans,
arrays and constrained atom unions retain their structure. Text-like types
(including UUIDs, decimals and dates) cross as strings. Unsupported optional
fields are omitted; unsupported required inputs or generic replies prevent
exposing that action. Updates and destroys require one primary-key field.

`AshEyg.effects(otp_app: :helpdesk)` returns the available effects. Pass only the
ones a script needs. The helpdesk's Gleam triage selector grants read and assign
actions; opening or closing a ticket is rejected before any action runs.
Actor, tenant and context are host options supplied to every action.
Ash policies and validations still apply.

## Run and keep packages

Supervise `{AshEyg.Session, name: Helpdesk.Scripts}` and call:

```elixir
AshEyg.Session.run(Helpdesk.Scripts, source,
  effects: AshEyg.effects(otp_app: :helpdesk), actor: current_user)
```

`check/3` returns a rendered type without performing effects. `run/3` returns an
EYG value; `AshEyg.inspect/1` renders it. Direct `AshEyg.check/3` and `run/3` take
a cache and return `{result, cache}` on success and failure.

The session owns an in-memory cache of interpreted package values, types and
release mappings. It fetches only missing referenced modules, validates CIDs
and pure modules, rolls back failed batches, and reuses successful loads across
calls. Separate sessions are independent. Restarting the owner clears its cache.
Use [full pins](./syntax.md#named-packages) for reproducible scripts; `@name`
uses the release mapping retained in that cache. Set `config :ash_eyg, hub: url`
to select a hub, or use `EYG_ORIGIN` in the helpdesk.

The [BEAM code server](https://www.erlang.org/doc/system/code_loading.html) loads
compiled Gleam/Elixir modules for the VM. An EYG cache is application data;
loading a package does not install a BEAM module or invoke hot-code replacement.
Applications in one VM must agree on shared compiled Gleam dependencies even
when their EYG sessions own separate caches.

`AshEyg.RunScript` runs a generic action's `source` argument with the action's
actor, tenant and context. Set its `session:` option to retain packages; without
one each call starts with an empty cache. Failures become an invalid `source`
argument. Add application effects with `AshEyg.Effect.new/4` when needed.

## Check the helpdesk

Checked with Elixir 1.20.4, OTP 27, Ash 3.36.0, Gleam and Bun. From the root:

```sh
cd examples/helpdesk
mix deps.get
cd browser
bun install
cd ..
mix assets.build
mix test
mix ash_eyg.effects
mix ash_eyg.check scripts/assign.eyg
mix ash_eyg.run scripts/assign.eyg
PORT=7816 mix phx.server
```

Open `http://localhost:7816/admin`, choose **Scripting → Script**, and run:

```eyg
perform SupportTicketOpen({subject: "Printer on fire"})
```

The source and returned record are highlighted. **Support → Ticket** shows the
created ticket. The `scripts` directory also contains assignment and scoped
triage examples. The test hooks invoke Gleam checks for triage restrictions,
actual assignments, retained packages and generic-action source errors.

To reproduce the browser check, run `gleam run -m tracing/package_fixture`
from `packages/tracing` and start the helpdesk with
`PORT=7816 EYG_ORIGIN=http://127.0.0.1:7207 mix phx.server`.
The fixture prints a full standard-package pin. Use it with `.list.map` to open
three tickets, then run another program with the same pin. The session makes
three package requests initially and none for the second call.

Run `gleam run -m tracing/ash_demo` from `packages/tracing`, with Playwright's
Chromium installed or `CHROME_BIN` set. It records source/result highlighting,
Unicode and scroll alignment, pinned package reuse, a type error before effects,
and the three created tickets. Output goes to `packages/tracing/recordings`.
