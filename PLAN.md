## Aims

Build a fully reproducible tracing and evaluation engine on top of overlay that completly tracks external state such as the filesystem, git respositories and databases (such as Neon DB with point-in-time queries)
The system will have complete determinism and state fidelity across agent executions.
By capturing sufficient environment pointers and side-effect logs alongside standard model telemetry.

The project will enable developers to:

- reconstruct the exact state of any historical execution step
- inspect the precise context the agent experienced
- replay agent behavior under identical conditions.
- evaluate prompt changes in the same environment.

## Decisions

Strictly separate observability (tracking model reasoning, prompts, and tool inputs/outputs via platforms like Langfuse) from state reconstruction (managing environment substrates, Git checkouts, and database states), linking them cleanly by storing state metadata pointers inside trace logs.

Only EYG code can be evaluated, this is deterministic as long as all side effects are recorded.
EYG code is always identified by a hash, code without explicit hashes will get pinned before executing.
This replaces the functionality of a tool like nix, and removes the need of anything like docker.

All effects called by the EYG program will recorded.
Effects will have their reply values recorded in a completly reproducable way.
For non recoverable effects such as a fetch, the full response needs to be capture.
For recorverable effects a pointer will be sufficient.
For example a `Clone` effect will return a git hash such that it can be replayed.
The `NeonQuery` effect will accept an optional point in time. If there is no point in time given the log will record the point in time so it can be replayed.

Traces will be uploaded to LangFuse, create a mock server for development.
In the web version all traces will be visible and themselves querable by the agent

When starting a chat session the secrets available to a program need mounting.
i.e. an effect `MountSecret(/user/:agent_or_task_id)` This is tracked with a hash but potentially it's not recoverable.
A replay should be possible by substituting dummy values, OR their are no secrets in the agent context and all effects add the required secret outside the traced run, such as in the `.overlay.eyg` file.

Effect Caching can be based on hashes, this needs to be careful for situations where the effect is not idempotent i.e. a point-in-time pointer not set.

Build a time travel debugger, You can scroll back in time and explore the file system at each point in the agent flow
Each effect on the file system is visible as a diff.
We probably not want to recreate all of the staging logic on git but there should be effects to commit as well.

Test mutation evaluations. change prompts, skill content (by changing what's mounted on the file system) and inspect the change.
These traces can stop if a query to an external service changes such as a web fetch. But for anything which is idemotent, i.e. a get to a resource that we trust doesn't change and/or something with a point-in-time key or a read to the file system.
We can proceed with new traces. 
This allows us to cohort test whole changes to the setup and evaluate the whole trajectory. We should particularly focus on cost of tokens in alternative traces.

The reproduction environment must work without an agent present. i.e. it should be possible to checkout a fresh REPL and use the Clone/Secret effects and get the same reproducability guarantees. There should be an export format for the environment so that other people can look at the sessions. This is a full replacement for nix, Should this be implemented with chroot or something else depends on memory requirement.

When running locally any file read will result in the file being added to the store of the reproduction.
