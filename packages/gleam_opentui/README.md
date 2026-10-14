# Gleam OpenTUI

Direct Gleam bindings to `@opentui/core` 0.5.14. Renderers, renderables, styles,
clipboard services and tree-sitter clients retain their native identity and
lifetime. Callers own rendering policy and must dispose of resources they create.
Fallible operations return `Result` rather than throwing into Gleam.

- `gleam_opentui`: renderers, nodes, input events and styles.
- `gleam_opentui/testing`: headless rendering, input simulation and frame capture.
- `gleam_opentui/clipboard`: native host clipboard services.
- `gleam_opentui/tree_sitter`: parser loading and performance counters.

Install JavaScript dependencies with `bun install --frozen-lockfile`, then run
`gleam test`. Consumers need `@opentui/core` 0.5.14 in their JavaScript environment.
The package has no dependency on EYG or any terminal application.
