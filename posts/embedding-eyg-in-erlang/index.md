---
title: Embedding EYG in an Erlang program
date: 2026-10-03
---

# Embedding EYG in an Erlang program

A running Erlang node is a great place for a script.
Connect a remote shell and you can call any function in the system.
That power is also the problem: one typo in a remote shell can stop a production system.

EYG is a scripting language where every interaction with the outside world is an effect, and the host decides which effects exist.
This post embeds EYG in an Erlang application so scripts can manage a supervisor of counters, and nothing else.

<video src="../../examples/erl_counter/video/erl-counter-observer.mp4" controls width="100%"></video>

The code is [`examples/erl_counter`](../../examples/erl_counter).
A second [video](../../examples/erl_counter/video/erl-counter.mp4) follows a script that uses the standard library from check to run.

## The application

The application is plain OTP.
A `one_for_one` supervisor starts counters on demand, each counter is a `gen_server` that adds one to its value every ten seconds.
Counter names are binaries used as child ids, so scripts never create atoms.

```erlang
%% counters_api.erl
start_counter(Name) -> ...
set_tick_rate(Name, Seconds) -> ...
get_value(Name) -> ...
shutdown(Name) -> ...
```

## Building EYG for Erlang

The EYG parser, type checker, interpreter and hub client are Gleam packages in the same repository.
Gleam compiles them for Erlang, so the example is built with `gleam` and depends on them by path.
The application itself is all Erlang, Gleam compiles any `.erl` file in `src` too.

```toml
# gleam.toml
name = "erl_counter"
target = "erlang"

[dependencies]
eyg_analysis = { path = "../../packages/gleam_analysis" }
eyg_hub = { path = "../../packages/gleam_hub" }
eyg_interpreter = { path = "../../packages/gleam_interpreter" }
eyg_ir = { path = "../../packages/gleam_ir" }
eyg_parser = { path = "../../packages/gleam_parser" }
gleam_crypto = ">= 1.6.0 and < 2.0.0"
gleam_httpc = ">= 5.0.0 and < 6.0.0"

[erlang]
application_start_module = "counters_app"
```

There is no adapter package, Erlang calls the Gleam modules directly.
A Gleam module `eyg/hub/cache` is the Erlang module `eyg@hub@cache`, strings are binaries and results are `{ok, Value}` or `{error, Reason}`.

## Effects

An effect has a label, the type of the value a script lifts to the host, and the type of the reply.
EYG types are plain terms, the unit type is `{record, empty}`.

```erlang
-define(TYPE, eyg@analysis@type_@isomorphic).

types() ->
    Reply = ?TYPE:result({record, empty}, string),
    Rate = ?TYPE:record([{<<"name">>, string}, {<<"seconds">>, integer}]),
    [
        {<<"StartCounter">>, {string, Reply}},
        {<<"SetTickRate">>, {Rate, Reply}},
        {<<"GetValue">>, {string, ?TYPE:result(integer, string)}},
        {<<"Shutdown">>, {string, Reply}}
    ].
```

The implementation is a function from label and lifted value to the reply.
EYG values keep their tags, `{string, <<"apples">>}` is the string `"apples"`.

```erlang
handle(<<"StartCounter">>, {string, Name}) ->
    reply(counters_api:start_counter(Name));
...

reply(ok) -> {tagged, <<"Ok">>, {record, #{}}};
reply({ok, Value}) -> {tagged, <<"Ok">>, {integer, Value}};
reply({error, Reason}) -> {tagged, <<"Error">>, {string, message(Reason)}}.
```

A duplicate or missing counter is an EYG `Error` value, scripts handle it like any other result.

## Check and run

`counters_eyg` has two functions.
Both take the source and a package cache, and both return `{Result, Cache}`.

```erlang
Cache0 = eyg@hub@cache:empty(),
{{ok, Type}, Cache1} = counters_eyg:check("perform StartCounter(\"apples\")", Cache0),
{{ok, Value}, Cache2} = counters_eyg:run("perform StartCounter(\"apples\")", Cache1).
```

Each call parses the script, loads the packages it refers to, then type checks it against exactly the counter effects.
`run` only executes a script that checks, so a mistake on the last line stops the effects on the first.

```
error: type mismatch given: Integer expected: String
hint: check the expression matches the expected type

 1 | perform StartCounter(1)
     ^^^^^^^^^^^^^^^^^^^^^^^
```

The inference context starts pure and permits only the host's effects.

```erlang
Context = ?INFER:with_effects(?INFER:pure(), counters_effects:types()),
Analysis = ?CACHE:infer_sync(?INFER:check(Context, Tree), Cache),
```

## Packages are loaded by reference

A script can refer to a package as `@standard`, `@standard:1` or by content id.
Nothing is preloaded, and `standard` is not special.
After parsing, `counters_packages` lists the script's references and loads only what they need from the hub, with their dependencies.
A script with no references, or whose references are cached, makes no requests.

The hub protocol, CID checks and dependency resolution are all existing `eyg_hub` functions.
Erlang supplies the HTTP and hashing, then drives the cache's actions until there is nothing left to do.

```erlang
drain(Cache0, Origin, Fetch, Hash, Trees) ->
    {Cache1, Actions} = ?CACHE:flush(Cache0),
    case Actions of
        [] -> {ok, Cache1, Trees};
        _ -> ... ?CACHE:compute(Action, Origin, Fetch, Hash) ... ?CACHE:update(...)
    end.
```

Every downloaded module is type checked before the cache is returned, so a script never runs against a package that does not check.

## The caller owns the cache

There is no hidden global cache.
The caller passes a cache in and keeps the one that comes back, even when the result is an error.
A corrected script then does not download its packages again.

The example keeps it in a `gen_server`, `counters_session`.

```erlang
handle_call({run, Source}, _From, Cache0) ->
    {Result, Cache1} = counters_eyg:run(Source, Cache0),
    {reply, Result, Cache1};
```

The remote shell in the video starts a session and only ever sees results.
Keeping the evaluated cache in a remote shell's variables stalled the shell, the session avoids that.

```erlang
{ok, S} = counters_session:start_link().
counters_session:run(S, "perform StartCounter(\"apples\")").
```

## Running a script

`run_step` drives the interpreter.
It stops at every reference and effect, and resumes with an answer.

```erlang
run_step(Step, Source, Cache) ->
    case ?CACHE:static_loop(Step, Cache, fun ?EXPR:resume/3) of
        {error, {{unhandled_effect, Label, Lift}, _Span, Env, K}} ->
            Reply = counters_effects:handle(Label, Lift),
            run_step(?EXPR:resume(Reply, Env, K), Source, Cache);
        {error, {Reason, Span, _Env, _K}} -> ... runtime diagnostic ...;
        {ok, Value} -> {ok, Value}
    end.
```

`static_loop` answers references with values from the cache.
An effect goes to the Erlang handler, and the program resumes where it stopped.

## Scripts in the video

A single effect.

```eyg
perform StartCounter("apples")
```

Several effects, the last reply is the result of the script.

```eyg
let _ = perform StartCounter("pears")
let _ = perform SetTickRate({name: "pears", seconds: 1})
perform GetValue("pears")
```

The standard library performing effects for every name in a list, it is fetched from the hub the first time.

```eyg
let names = ["plums", "figs", "limes", "kiwis"]
@standard.list.map(names, (name) -> {
  let _ = perform StartCounter(name)
  perform SetTickRate({name: name, seconds: 2})
})
```

Opening Observer on the node shows a child of `counters_sup` for every counter.
Double click one to see its state.

```erlang
#{name => <<"apples">>, seconds => 10, value => 1, timer => #Ref<...>}
```

## What the host still trusts

Type checking guarantees a script only performs the counter effects, with the right types.
It does not limit how long a script runs, and execution is not transactional, a runtime failure does not undo earlier effects.

## Try it

```sh
cd examples/erl_counter
gleam build
erl -sname counters -pa build/dev/erlang/*/ebin \
  -eval '{ok, _} = application:ensure_all_started(erl_counter).'
```
