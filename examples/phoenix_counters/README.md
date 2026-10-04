# Phoenix counters

A Phoenix application where EYG scripts, typed into the home page, control a supervisor of counters.

The same example in Erlang is [`examples/erl_counter`](../erl_counter), this one follows its design.

- `PhoenixCounters.Counters` starts named counters under a `DynamicSupervisor`, each ticks every 10 seconds.
- `PhoenixCounters.Counters.Effects` gives each function an EYG effect, a type and an implementation.
- `PhoenixCounters.Counters.Eyg` checks and runs scripts that can use only those effects.
  Both take a package cache and return `{result, cache}`.
- `PhoenixCounters.Counters.Packages` loads the packages a script refers to from the [hub](https://eyg.run).
- `PhoenixCounters.Scripts` is the process that owns the cache, every check and run goes through it.
- `PhoenixCountersWeb.HomeLive` type checks every program that parses as it is typed, enter runs it.

The script box highlights EYG in the browser with [shiki](https://shiki.style) and the TextMate grammar from [`packages/vscode-eyg`](../../packages/vscode-eyg).

## Packages

Scripts can use any package on the hub, i.e. `@standard`.
Nothing is preloaded, a check or run fetches what the script refers to, with its dependencies.
`PhoenixCounters.Scripts` keeps the cache, so each package is fetched once.

Set the hub with the `:hub` setting, it is `https://eyg.run` by default.

```elixir
config :phoenix_counters, hub: "http://localhost:8001"
```

## Building EYG

The EYG libraries are Gleam packages in this repository and are not published for Erlang, so Mix cannot fetch them.
[`gleam/gleam.toml`](gleam/gleam.toml) lists them, and the `gleam_libraries` compiler in [`mix.exs`](mix.exs)
builds them with Gleam and copies their modules into this application.
The Gleam project has its own directory because Gleam would also compile the Elixir files in `test`.

## Run

Requires Elixir, Gleam and a JavaScript package manager for shiki.

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

```eyg
@standard.list.map(["plums", "figs"], (name) -> {
  perform StartCounter(name)
})
```

## Test

```sh
mix test
```

The tests serve packages with the hub's own codecs from a fixture, they make no requests.
