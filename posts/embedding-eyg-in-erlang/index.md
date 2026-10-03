---
title: Embedding EYG in an Erlang program
date: 2026-10-03
---

# Embedding EYG in an Erlang program

A running Erlang node is a great place for a script.
Connect a remote shell and you can call any function in the system.
That power is also the problem: one typo in a remote shell can stop a production system.

EYG is a scripting language where every interaction with the outside world is an effect, and the host decides which effects exist.
In this post we embed EYG in an Erlang application so scripts can manage a supervisor of counters, and nothing else.

<video src="demo.mp4" controls width="100%"></video>

The code is in [`examples/erlang_counters`](../../examples/erlang_counters).

## The application

The application is plain OTP.
A `simple_one_for_one` supervisor starts counters on demand, each counter is a `gen_server` that adds one to its value every ten seconds.

```erlang
%% counters_api.erl
start_counter(Name) -> ...
set_tick_rate(Name, Seconds) -> ...
get_value(Name) -> ...
shutdown(Name) -> ...
```

Counters are registered by name with `global`, so a name is all a script needs to refer to one.

## Depending on EYG

The EYG parser, type checker and interpreter are written in Gleam, which compiles to Erlang.
[`eyg_beam`](../../packages/eyg_beam) wraps them in three functions for Erlang and Elixir hosts:

- `eyg_beam:check(Source, Effects, Packages)` returns `{ok, Type}` or `{error, Errors}`.
- `eyg_beam:run(Source, Effects, Packages, Handler)` checks then runs, returning `{ok, Value}` or `{error, Errors}`.
- `eyg_beam:load_package(Json)` loads a module for scripts to use as `@name`.

The example has no Gleam source, but it is built with `gleam` so that it can depend on `eyg_beam` by path.
Gleam compiles any `.erl` files in `src` and writes the `.app` file.

```toml
# gleam.toml
name = "counters"
target = "erlang"

[dependencies]
eyg_beam = { path = "../../packages/eyg_beam" }

[erlang]
application_start_module = "counters_app"
```

## Effects

An effect has a label, the type of the value a script lifts to the host, and the type of the reply.
EYG types are plain Erlang terms: `string`, `integer`, `{record, Rows}` and so on.

```erlang
effects() ->
    Reply = eyg_beam:result_type({record, empty}, string),
    [
        {<<"StartCounter">>, {string, Reply}},
        {<<"SetTickRate">>, {eyg_beam:record_type([{<<"name">>, string}, {<<"seconds">>, integer}]), Reply}},
        {<<"GetValue">>, {string, eyg_beam:result_type(integer, string)}},
        {<<"Shutdown">>, {string, Reply}}
    ].
```

The implementation is a function from label and lifted value to the reply.
Values are plain terms too, `{string, <<"apples">>}` is the EYG string `"apples"`.

```erlang
handle(<<"StartCounter">>, {string, Name}) ->
    reply(Name, counters_api:start_counter(Name));
handle(<<"SetTickRate">>, {record, #{<<"name">> := {string, Name}, <<"seconds">> := {integer, Seconds}}}) ->
    reply(Name, counters_api:set_tick_rate(Name, Seconds));
...

reply(_Name, ok) -> {tagged, <<"Ok">>, {record, #{}}};
reply(_Name, {ok, Value}) -> {tagged, <<"Ok">>, {integer, Value}};
reply(Name, {error, Reason}) -> {tagged, <<"Error">>, {string, message(Name, Reason)}}.
```

Errors from the API become EYG `Error` values, so scripts handle them like any other result.

## Checking and running

`counters_eyg` is the module you call from a shell.
Both functions type check the script against only the counters effects and pretty print any errors.

```erlang
check(Source) ->
    case eyg_beam:check(to_binary(Source), counters_effects:effects(), packages()) of
        {ok, Type} -> io:format("~ts~n", [Type]), ok;
        {error, Errors} -> io:format("~ts~n", [Errors]), error
    end.

run(Source) ->
    Handler = fun counters_effects:handle/2,
    case eyg_beam:run(to_binary(Source), counters_effects:effects(), packages(), Handler) of
        {ok, Value} -> io:format("~ts~n", [eyg_beam:inspect(Value)]), {ok, Value};
        {error, Errors} -> io:format("~ts~n", [Errors]), error
    end.
```

A script that uses an effect the host does not provide, or passes the wrong type to one, is rejected before anything happens.

```
(counters@host)3> counters_eyg:check("perform StartCounter(1)").
error: type mismatch given: Integer expected: String
hint: check the expression matches the expected type

 1 | perform StartCounter(1)
     ^^^^^^^^^^^^^^^^^^^^^^^
error
```

This matters most for scripts with several steps.
If the third step is wrong, the first two never run, so there is no half finished change to clean up.

## Scripts in the video

Start the node, then join the cluster with a remote shell.

```sh
bin/start
erl -sname dev -setcookie eyg -remsh counters@$(hostname -s)
```

The first script performs a single effect.

```erlang
counters_eyg:run("perform StartCounter(\"apples\")").
```

The second performs several, each result is a value the script can use.

```erlang
counters_eyg:run("
  let _ = perform StartCounter(\"pears\")
  let _ = perform SetTickRate({name: \"pears\", seconds: 1})
  perform GetValue(\"pears\")
").
```

The third uses the standard library to perform effects for every item in a list.

```erlang
counters_eyg:run("
  let names = [\"plums\", \"figs\", \"limes\", \"kiwis\"]
  @standard.list.map(names, (name) -> {
    let _ = perform StartCounter(name)
    perform SetTickRate({name: name, seconds: 2})
  })
").
```

`@standard` is loaded once when the application starts, from the IR of the standard library in this repository.

```erlang
{ok, Json} = file:read_file(Path),
{ok, Standard} = eyg_beam:load_package(Json),
persistent_term:put({?MODULE, packages}, #{<<"standard">> => Standard}).
```

Running `observer:start()` from the remote shell opens observer on the node.
The Applications tab shows a child of `counters_sup` for every counter a script started, and double clicking one shows its state.

```erlang
#{name => <<"apples">>, seconds => 10, value => 1, timer => #Ref<...>}
```

## What the host still trusts

Type checking guarantees a script only performs the effects you list, with the types you declared.
It does not limit how long a script runs, a recursive script can loop forever in the calling process.
The handler runs in the caller's process too, so a crash in an effect implementation crashes the caller like any other function call.

## Try it

```sh
git clone https://github.com/crowdhailer/eyg-lang
cd eyg-lang/examples/erlang_counters
bin/start
```
