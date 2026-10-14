---
name: Embedding EYG in Elixir
description: Use a Gleam EYG runtime from Phoenix LiveView with typed counter effects and an application-owned cache.
---

# Embedding EYG in Elixir

[Watch the checked Phoenix walkthrough](/glasshouse/phoenix-counters.webm).
The [example](../examples/phoenix_counters/) uses Phoenix templates and OTP
callbacks, with EYG evaluation, package loading, counter state and browser
behavior implemented in Gleam.

## Start the example

Checked with Elixir 1.20.4 and OTP 27; the project also needs Gleam and Bun.
Use a [compatible Elixir/OTP pair](https://elixir.hexdocs.pm/compatibility-and-deprecations.html).
From the repository root:

```sh
cd examples/phoenix_counters
mix deps.get
cd browser
bun install
cd ..
mix assets.setup
mix assets.build
mix test
PORT=7815 mix phx.server
```

Open `http://localhost:7815`. Type this program and press Enter:

```eyg
let _ = perform StartCounter("apples")
let _ = perform SetTickRate({name: "apples", seconds: 1})
perform GetValue("apples")
```

The counter appears in the table and ticks once a second. Programs are checked
as you type; incomplete programs wait for more text. Enter runs a complete
program, Shift+Enter inserts a newline, and a successful run clears the input.
The editor retains Unicode text and synchronizes its highlighted copy when
scrolling. The theme controls also run in Gleam.

`StartCounter`, `SetTickRate`, `GetValue` and `Shutdown` are application effects.
Their signatures and replies are in `gleam/src/phoenix_counter/effects.gleam`.
The host bridges call the counter API. A type error anywhere prevents every
effect, including effects earlier in the program.

## Own the cache

`PhoenixCounters.Counters.Eyg.check(source, cache)` and `run(source, cache)`
return `{result, cache}` on success and failure. The shared
[Gleam runtime](../packages/gleam_embedding/) fetches only referenced modules,
checks their CIDs and types, and preserves the original cache after a failed
batch. A script error can retain packages that loaded successfully.

`PhoenixCounters.Scripts` is supervised with the application and owns a cache
shared by LiveViews. Calls are serialized through that process; only results
cross the boundary. Cached references make no requests. Restarting the owner
discards its in-memory packages. Separate caches are independent.

The [BEAM code server](https://www.erlang.org/doc/system/code_loading.html)
loads compiled Gleam and Elixir modules for the VM. EYG packages are interpreted
values, types and release mappings stored by the application process. Loading
one does not create a BEAM module or invoke BEAM hot-code replacement.

The Mix compiler hook invokes Gleam's BEAM installer because these libraries
are local dependencies. Applications sharing a VM must use compatible compiled
Gleam dependencies: their module names belong to that VM. The EYG caches remain
independently owned application data.

Use [pinned references](./syntax.md#named-packages) for repeatable scripts.
`@name` uses the release mapping loaded into the retained cache.

## Reproduce the browser check

In another terminal, start the repository package fixture:

```sh
cd packages/tracing
gleam run -m tracing/package_fixture
```

Start Phoenix with
`PORT=7815 EYG_ORIGIN=http://127.0.0.1:7207 mix phx.server`.
The fixture serves the checked standard IR and prints a full pin. Use that
reference followed by `.list.map(...)` to create several counters.

Run `gleam run -m tracing/phoenix_demo` from `packages/tracing`, with Playwright's
Chromium installed or `CHROME_BIN` set. The walkthrough checks actual LiveView
events, Unicode highlighting, scrolling, Enter/Shift+Enter, clearing, counter
effects, type errors before effects, theme changes and three initial package
requests followed by cache reuse. The browser recording is saved in
`packages/tracing/recordings`.
