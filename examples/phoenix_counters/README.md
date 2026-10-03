# Phoenix counters

A Phoenix application where EYG scripts, typed into the home page, control a supervisor of counters.

The same example in Erlang is [`examples/erlang_counters`](../erlang_counters).

- `PhoenixCounters.Counters` starts named counters under a `DynamicSupervisor`, each ticks every 10 seconds.
- `PhoenixCounters.Counters.Effects` gives each function an EYG effect, a type and an implementation.
- `PhoenixCounters.Counters.Eyg` checks and runs scripts that can use only those effects.
- `PhoenixCountersWeb.HomeLive` type checks every program that parses as it is typed, enter runs it.

The script box highlights EYG in the browser with [shiki](https://shiki.style) and the TextMate grammar from [`packages/vscode-eyg`](../../packages/vscode-eyg).

## Run

Requires Elixir, Gleam, to build [`eyg_beam`](../../packages/eyg_beam), and a JavaScript package manager for shiki.

```sh
(cd assets && bun install)
mix setup
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000), set `PORT` to use another port.

```eyg
let _ = perform StartCounter("apples")
let _ = perform SetTickRate({name: "apples", seconds: 1})
perform GetValue("apples")
```

Scripts can use the standard library as `@standard`, it is loaded from `eyg_packages/standard/index.eyg.json`.

## Test

```sh
mix test
```
