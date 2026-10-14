# Phoenix counters with EYG

Script supervised counters from a Phoenix LiveView. Native Elixir templates,
callbacks and registry/supervisor calls are the host glue. Counter state,
effect signatures/replies, EYG execution, validated package loading, browser
editing and build tools are Gleam.

Follow the [Elixir embedding guide](../../guides/embedding_elixir.md) and
[watch the checked browser walkthrough](../../packages/tracing/recordings/phoenix-counters.webm).

```sh
mix deps.get
cd browser
bun install
cd ..
mix assets.setup
mix assets.build
mix test
PORT=7815 mix phx.server
```

`gleam/` builds the shared EYG libraries and application logic for BEAM.
`browser/` builds LiveView hooks, syntax highlighting and themes for JavaScript.
Phoenix and Shiki bindings live in dedicated packages; native DOM bindings are
in Plinthx. Icon CSS is generated from the installed Heroicons SVGs in Gleam.

The native ExUnit hooks call Gleam integration checks for loading, cache reuse,
failed batches, checks before effects, process ownership, timer cancellation
and domain errors. The browser checks are in `tracing/phoenix_demo`.
`EYG_ORIGIN` selects the hub, and `PORT` selects the HTTP port.
