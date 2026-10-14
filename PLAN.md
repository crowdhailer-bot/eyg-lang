# Immutable sandbox milestone

The first platform milestone is implemented; usage and the precise execution
contract are documented in [guides/sandbox.md](guides/sandbox.md).

## Architecture

- Fetchers acquire inputs into content-addressed blobs/trees.
- Preparation pins an entry's transitive module closure before execution.
- Environments include filesystem, explicit variables, hub origin, clock, seed
  and a runtime semantics version. Private forks share immutable inputs.
- One external broker handles models and other HTTP services, with ordered
  replay and explicit live-host permissions. There are no service-specific
  cache/reconstruction rules.
- Output environments, observations and EYG journals are content addressed.
  Local runs share blocks; portable bundles/archives include the full closure.
- Interpreter slices support yielding/cancellation; synchronous runners have a
  finite reduction budget and the sandbox has additional IO budgets.

## Acceptance checks

- Portable execution/replay without the original checkout or network.
- Host files and variables cannot influence a sealed execution.
- Forks cannot observe each other's writes.
- Missing inputs and external divergence fail explicitly.
- Repeated identical requests preserve their different ordered responses.
- Pure runaway computation yields/stops and another process can complete.
- A retained 1,000-fork benchmark verifies physical sharing of a 4 MiB input.

## Further platform work

- Preemptive worker scheduling and hard heap limits for adversarial workloads.
- Bounded streaming transports and deadlines.
- Crash-safe incremental journal persistence and store garbage collection.
- Structural sharing of full model request histories.
- Credential capabilities supplied outside portable input environments.
