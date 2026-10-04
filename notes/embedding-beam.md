---
name: Embedding EYG in BEAM hosts
description: Why the examples build Gleam libraries locally and keep host package loaders
date: 2026-10-04
---

The Erlang, Phoenix, and Ash integrations use the public EYG libraries directly.
The earlier `eyg_beam` adapter duplicated existing APIs and cache data structures;
it was removed from the source work before consolidation.

Mix cannot currently fetch Erlang releases of these EYG libraries. The Phoenix
example and `ash_eyg` therefore build a small `gleam/` project and copy its BEAM
modules into the application. The separate directory prevents Gleam from trying
to compile the Elixir tests. Two such libraries in one application would duplicate
their Gleam dependencies; publishing Erlang builds is the longer-term solution.

The BEAM loaders deliberately preserve their stronger validation contract:
reject ill-typed fetched modules and return the original cache after a failed
batch. `eyg_hub.cache.load` drives fetching but does not enforce that contract.
Replacing the three host loaders with it would require retaining those checks.
The example tests cover cache ownership, reference forms, and failure behavior.

No CLI effects were added. Each example defines application effects at its host
boundary; HTTP and hashing for package loading are host operations.
