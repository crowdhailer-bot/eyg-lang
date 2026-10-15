---
name: Roadmap source disposition
description: Source revisions and consolidation choices behind the roadmap branch.
date: 2026-10-15
---

The consolidation starts at `8e2fd588`. Source refs were checked against both
remotes on this date; local rebases were not additional feature branches.

| Reviewed source | Pinned revision | Retained work |
| --- | --- | --- |
| bot/overlay-review | `bac77b5ae4bd082737d0fa1e50dbf2450f55293d` | Trajectories, artifacts, contexts, evals, providers, articles and talk |
| bot/overlay-tui | `2a90fdedf60e0bd07b6e51cdb1074c9c6df75b7f` | Shared terminal runtime, three frontends, prompt controls and benchmarks |
| bot/next | `0539e8baec6f228c6db04c4d3807d515277794dd` | Language/runtime improvements and later artifact, eval and terminal refinements |
| origin/nixish | `2b0c95e93ccfdaaa8e6710b55179fad782fb71ec` | Acquisition, sealed inputs, forks, package closure and Nix fetcher |
| origin/tracing | `bda1a6e9f1ace8d849d82addbf4cd9346d2a627d` | Effect/function spans, captures, offline viewer and exports |
| origin/handler | `5fc6bbabdc441f96c22efee14ecfbbaed9fe8a4b` | Deep/shallow handlers, masks, purity and ordered effect tests |
| bot/harnesses | `6d7d0efe69ede7feb500a9549e5074c317678c18` | Policy runtime, Pi/OpenCode adapters, inherited child policies and design prose |
| origin/claude/vigilant-maxwell-eq2ob6 | `fd4fbf75917c04c812e122cb91c29fb06d4304e9` | Pi image, native boot, input/display effects and games |

The additional embedding source `bot/embedding` at
`6f2c19a2768c1028fdbddbb0e43e0bb6f94edcd5` supplies the BEAM and browser examples.
The roadmap proceeds through trajectories (`df5d233a`), sandbox (`092f7bad`),
artifacts (`a87f3206`), TUI (`620def3b`), embedding (`3629dfb3`), then the remaining
work. The original `f0bd95d9` PLAN is preserved independently in `370caa6e`.
Fixes precede their consumers, and later commits extend the consolidated paths.

The final fetcher contract replaces intermediate Clone/service-effect designs.
All examples use that contract. Runtime logic, browser controllers and tooling
were ported to Gleam; native host entrypoints retain only the necessary glue.
Base platform bindings live in plinthx; external library bindings live with
their packages. OpenCode/Pi vendor trees were replaced with pinned official SDKs
and a checked installer for the native OpenCode dispatcher. Public OpenCode hooks
and the native dispatcher remain separate integration levels.

Historical model reports, talk claims and the older TypeScript benchmark samples
are labelled historical. Fresh bounded replay and native benchmark measurements
are reported separately. The real local Qwen call failed the required protocol;
scripted model fixtures are identified as fixtures. Browser-core, stronger
artifact isolation and durable SDK session storage remain explicit proposals.
The Pi videos show a booted QEMU image, without claiming physical hardware checks.

Final local checks covered all 49 JavaScript matrix entries (44 test packages,
five build-only), all 13 BEAM library entries, the native Erlang/Elixir/Ash hosts,
76 hub database tests, compiler freshness, task validators, the pinned OpenCode
dispatcher and all 370 root EYG tests with the freshly compiled CLI. Real artifact
checks passed again after regenerating the preview bundles. Sealed debugger
captures were regenerated for runtime 3 and have a compatibility regression test.
Guides link their checked recordings and describe real Jaeger, Langfuse, Nix and
browser checks. The CI workflow was checked locally with actionlint; this audit
does not claim a completed remote CI run.

Old local branches and stashes can now be removed. The unrelated local bdriver
and datalog experiments were outside the eight requested source branches; their
remote branches remain available. Remote source refs are preserved.
