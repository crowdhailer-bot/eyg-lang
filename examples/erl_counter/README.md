# Erlang counters with EYG

An OTP application with supervised counters, scripted through typed EYG effects.
Gleam owns counter state, effect replies, parsing, checking and evaluation.
The Erlang files marshal native calls and implement application, supervisor,
GenServer, configuration and timer callbacks.

```sh
gleam build --warnings-as-errors
gleam test
erl -sname counters -pa build/dev/erlang/*/ebin
```

Follow the [Erlang embedding guide](../../guides/embedding_erlang.md) and
[watch the checked console workflow](video/erlang-counters.mp4).
The recorder is `tracing/erlang_demo`, implemented in Gleam.

`counters_eyg:check/2` and `run/2` take source and a cache, and return
`{Result, Cache}` on success and failure. Their one-argument conveniences
start empty and print the result. `counters_session` retains a cache in a
GenServer so callers can reuse packages without passing the whole cache.

Package loading and evaluation delegate to
[`eyg_embedding`](../../packages/gleam_embedding/). Tests cover checks before
effects, diagnostics, sequential actions, domain error values, cancelled timers
and session reuse of the actual standard package. The shared library covers
reference forms, dependency loading, corrupt modules and failed batch rollback.
