# Erlang counters

An Erlang application where EYG scripts control a supervisor of counters.

Every counter ticks every 10 seconds, adding one to its value.
`counters_api` has the functions `start_counter`, `set_tick_rate`, `get_value` and `shutdown`.
`counters_effects` gives each function an EYG effect, a type and an implementation.
`counters_eyg` checks and runs scripts that can use only those effects.

| Effect         | Lift                               | Reply                    |
| -------------- | ---------------------------------- | ------------------------ |
| `StartCounter` | `String`                           | `Result({}, String)`      |
| `SetTickRate`  | `{name: String, seconds: Integer}` | `Result({}, String)`      |
| `GetValue`     | `String`                           | `Result(Integer, String)` |
| `Shutdown`     | `String`                           | `Result({}, String)`      |

The source is all Erlang. It is built with `gleam` so it can depend on [`eyg_beam`](../../packages/eyg_beam) from this repository.

## Run

Requires Erlang and Gleam.

```sh
bin/start
```

This starts the node `counters@<host>` with the cookie `eyg`.

```erlang
1> counters_eyg:run("perform StartCounter(\"apples\")").
Ok({})
{ok,{tagged,<<"Ok">>,{record,#{}}}}
2> counters_eyg:check("perform StartCounter(1)").
error: type mismatch given: Integer expected: String
hint: check the expression matches the expected type

 1 | perform StartCounter(1)
     ^^^^^^^^^^^^^^^^^^^^^^^
error
```

Scripts can use the standard library as `@standard`, it is loaded from `eyg_packages/standard/index.eyg.json`.

```erlang
3> counters_eyg:run("
  @standard.list.map([\"a\", \"b\", \"c\"], (name) -> {
    let _ = perform StartCounter(name)
    perform SetTickRate({name: name, seconds: 1})
  })
").
```

## Join the cluster

Open a shell on the running node from another terminal.

```sh
erl -sname dev -setcookie eyg -remsh counters@$(hostname -s)
```

Watch the counters with observer from its own node, then pick `counters@<host>` from the Nodes menu.
The Applications tab shows the `counters_sup` children, double click a counter to inspect its state.

```sh
erl -sname observer -setcookie eyg -hidden -run observer
```

## Test

```sh
gleam test
```
