# Ash helpdesk with EYG

The Ash getting-started resources, exposed through the shared Gleam runtime.
`SupportTicketOpen`, read, close and assign actions are typed EYG effects.
`Helpdesk.Scripts` owns the package cache; the Gleam triage selector grants only
read and assign actions. A generic action makes scripts available in AshAdmin.

The [Ash guide](../../guides/embedding_ash.md) has setup commands, cache/code-server
comparisons and a checked browser recording. Build with Elixir 1.20, OTP 27,
Gleam and Bun:

```sh
mix deps.get
cd browser
bun install
cd ..
mix assets.build
mix test
PORT=7816 mix phx.server
```

Visit `/admin`, choose **Scripting → Script**, and run an EYG program. The
`scripts` directory contains opening, assignment and scoped triage examples.
`mix ash_eyg.effects`, `check` and `run` inspect or execute them.

Execution, package loading, type/value conversion, effect selection, highlighting
and build/recording tooling are Gleam. Native Elixir retains resource DSLs,
framework callbacks, host action calls and supervision. The browser uses the
dedicated Shiki bindings and native DOM operations in `plinthx`; it shares the
generated grammar data with the Phoenix example. The bundler checks that data
against the VS Code grammar.

The four ExUnit hooks invoke Gleam checks for restricted triage scripts, actual
ticket assignments, generic-action cache reuse and source errors. The real
browser check is `tracing/ash_demo`; it verifies three initial HTTP package
requests and reuse on the next script.
