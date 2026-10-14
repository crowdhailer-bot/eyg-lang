---
name: Embedding EYG in Erlang
description: Script supervised OTP counters through a Gleam runtime and an explicitly owned package cache.
---

# Embedding EYG in Erlang

[Watch the checked Erlang console](/glasshouse/erlang-counters.mp4).
The [example](../examples/erl_counter/) uses native OTP lifecycle callbacks
and a shared [Gleam embedding runtime](../packages/gleam_embedding/).

From the repository root:

```sh
cd examples/erl_counter
gleam build --warnings-as-errors
gleam test
erl -sname counters -pa build/dev/erlang/*/ebin
```

In the Erlang console:

```erlang
{ok, _} = application:ensure_all_started(erl_counter).
Cache0 = eyg@hub@cache:empty().
{{ok, _Type}, Cache1} = counters_eyg:check("perform StartCounter(\"a\")", Cache0).
{{ok, _Started}, Cache2} = counters_eyg:run("perform StartCounter(\"a\")", Cache1).
{{ok, _Rate}, Cache3} = counters_eyg:run("perform SetTickRate({name: \"a\", seconds: 1})", Cache2).
{{ok, _Value}, Cache4} = counters_eyg:run("perform GetValue(\"a\")", Cache3).
{{ok, _Stopped}, Cache5} = counters_eyg:run("perform Shutdown(\"a\")", Cache4).
```

`check` parses, loads referenced packages and checks against the allowed effects;
it starts no counters. `run` performs the same checks before evaluation. An
ill-typed later operation prevents earlier effects from running. Each operation
returns `Result`: duplicate names, missing counters and invalid rates become EYG
`Error` values. Names remain binaries and are not converted into dynamic atoms.

| Effect | Input | Reply |
| --- | --- | --- |
| `StartCounter` | String | Result({}, String) |
| `SetTickRate` | {name: String, seconds: Integer} | Result({}, String) |
| `GetValue` | String | Result(Integer, String) |
| `Shutdown` | String | Result({}, String) |

These are application effects. The host provides their implementations and
types; the CLI's effect set is unchanged.

## Package ownership

Every `check/2` and `run/2` returns the cache, including on errors. Keep it for
the next call. Missing modules load through the hub's codecs and CID checks;
downloaded modules must be pure and well typed. A failed batch preserves the
original cache. A valid batch remains available after a script error.

For several callers, keep the cache in an OTP process:

```erlang
{ok, Session} = counters_session:start_link().
counters_session:check(Session, "!int_add(20, 22)").
counters_session:run(Session, "!int_add(20, 22)").
gen_server:stop(Session).
```

Only results cross the process boundary. Cached references make no requests.
Separate empty caches are independent; restarting their owner discards its
in-memory packages. Names use the release mapping loaded into that cache;
use [full pins or content references](./syntax.md#named-packages) for scripts
that must identify the same code across sessions.

The [BEAM code server](https://www.erlang.org/doc/system/code_loading.html)
loads compiled Gleam and Erlang modules for the VM. It supports current and old
module code. The EYG cache holds interpreted values, inferred types and release
mappings in the owning process. An EYG package is not loaded as a BEAM module;
retaining or replacing that cache does not invoke BEAM hot-code replacement.

## Reproduce the recording

Start a deterministic HTTP hub in another terminal:

```sh
cd packages/tracing
gleam run -m tracing/package_fixture
```

It serves the repository's standard IR and prints its fully pinned reference.
In the Erlang console, configure the origin and set `Ref` to that printed string:

```erlang
application:set_env(erl_counter, hub, <<"http://127.0.0.1:7207">>).
{ok, S} = counters_session:start_link().
{ok, Type} = counters_session:check(S, Ref ++ ".list.map([1, 2], (n) -> { n })").
{ok, _} = counters_session:run(S, Ref ++ ".list.map([\"b\", \"c\"], (name) -> { perform StartCounter(name) })").
counters_session:cached(S, {package, <<"standard">>}).
```

The first check makes three requests; the following run reuses the cache.
The recording also changes a real counter's rate and confirms that a rejected
script never created its counter. With Xvfb, xterm, tmux and ffmpeg installed,
run `gleam run -m tracing/erlang_demo` from `packages/tracing` to regenerate it.
The recorder starts and stops its own hub and terminal processes.
