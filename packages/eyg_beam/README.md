# eyg_beam

Check and run [EYG](https://eyg.run) programs from Erlang and Elixir hosts.

A host lists the effects it handles, each with the type of the value a program lifts and the type of the reply.
Programs are type checked against only those effects before they run.

```erlang
Effects = [{<<"Add">>, {integer, integer}}],
Handler = fun(<<"Add">>, {integer, N}) -> {integer, N + 1} end,

{ok, <<"Integer">>} = eyg_beam:check(<<"perform Add(1)">>, Effects, #{}),
{ok, {integer, 2}} = eyg_beam:run(<<"perform Add(1)">>, Effects, #{}, Handler).
```

Errors are returned as text, rendered against the source.

```
error: missing row 'Log'
hint: the record or union is missing 'Log'

 1 | perform Log("hi")
     ^^^^^^^^^^^^^^^^^
```

## Types and values

Types and values are the terms of `eyg/analysis/type_/isomorphic` and `eyg/interpreter/value`.

| EYG                  | type                                                | value                                       |
| -------------------- | --------------------------------------------------- | ------------------------------------------- |
| `5`                  | `integer`                                           | `{integer, 5}`                              |
| `"hi"`               | `string`                                            | `{string, <<"hi">>}`                        |
| `[1]`                | `{list, integer}`                                   | `{linked_list, [{integer, 1}]}`             |
| `{name: "Ada"}`      | `eyg_beam:record_type([{<<"name">>, string}])`      | `{record, #{<<"name">> => {string, <<"Ada">>}}}` |
| `Ok({})`             | `eyg_beam:result_type({record, empty}, string)`     | `{tagged, <<"Ok">>, {record, #{}}}`         |

## Packages

Programs refer to packages as `@name`.
Load a package from its IR JSON and pass it to `check` and `run` by name.

```erlang
{ok, Json} = file:read_file("eyg_packages/standard/index.eyg.json"),
{ok, Standard} = eyg_beam:load_package(Json),
Packages = #{<<"standard">> => Standard}.
```

Only the bare `@name` form is resolved, nothing is fetched from a hub.

## Using from a host

`eyg_beam` and the EYG packages it builds on target JavaScript on Hex, so a host builds them from this repository.

- A Gleam project, including one whose source is all Erlang, adds `eyg_beam = { path = "..." }`, see [`examples/erlang_counters`](../../examples/erlang_counters).
- A Mix project adds `{:eyg_beam, path: "..."}`, Mix builds it with `make`, which bundles `eyg_beam` and its Gleam dependencies into one OTP application in `ebin/`.
  Building needs `gleam` on the path. See [`examples/phoenix_counters`](../../examples/phoenix_counters).
