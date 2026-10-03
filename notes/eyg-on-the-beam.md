---
name: EYG on the BEAM
description: How Erlang and Elixir hosts get EYG while the packages are JavaScript only on Hex
date: 2026-10-03
---

`eyg_parser`, `eyg_analysis` and `eyg_interpreter` build for Erlang, but their Hex releases are JavaScript only and ship no Erlang source.
So BEAM hosts build them from this repository through `eyg_beam`.

- A Gleam project depends on `eyg_beam` by path, `examples/erlang_counters` is all Erlang built with `gleam` for this reason.
- Mix cannot build Gleam, so `eyg_beam`'s Makefile merges it and every Gleam dependency into one OTP application in `ebin/`.
  A host that also uses `gleam_stdlib` from Hex would load two copies of its modules.

Publishing the EYG packages for Erlang would remove both workarounds.
