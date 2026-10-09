# pi extension

A [pi](https://pi.dev) extension that adds an `eyg` tool.
Every effect of the agent's EYG program is decided by a policy written in EYG, and pi's other tools are effects too:
`read` is `perform Read({path: "README.md"})`, an MCP tool `mcp__github__search` is `McpGithubSearch`.

It uses the same policy runtime as the [opencode plugin](../opencode_plugin/), configuration and policies are written the same way.
Pi is vendored, unchanged, in [`vendor/pi-mono`](../../vendor/pi-mono/), the extension needs nothing from pi beyond its extension API.

## Build

```sh
bun run build
```

This builds the Gleam runtime in `../opencode_plugin` and bundles it with the extension into `dist/index.js`.
Pi's packages and TypeBox are left as imports, pi provides them to extensions.

## Install

```sh
mkdir -p .pi/extensions/eyg
cp dist/index.js .pi/extensions/eyg/index.js
# or ~/.pi/agent/extensions/eyg/ for every project, or `pi -e path/to/dist/index.js` once
```

## Levels

1. `src/bash-only-eyg.ts` is a separate extension that blocks every `bash` command except a single `eyg` command.
2. The `eyg` tool, with the default policy when there is no configuration: files in the project can be read and changed and nothing else.
3. A policy in `.pi/eyg.eyg`, `~/.pi/agent/eyg.eyg` or the file named by `PI_EYG_CONFIG`, see the [opencode plugin](../opencode_plugin/README.md#configuration) for the format.
   Fields for pi's tools are the tool names in snake case, `read`, `bash`, `edit`, `write`.
   Arguments are snake case in EYG and mapped back to the tool's schema.
4. `--eyg-only`, or `PI_EYG_ONLY=1`, gives the model only the `eyg` tool.
   Pi's other tools stay active, so they can still be called as effects, but their declarations are left out of requests (`prepareLoadout` and `hiddenDeclarations`).

`Task({agent, prompt, policy})` starts a subagent, an in-process pi-agent-core `Agent` whose only tool is `eyg`.
Its policy is the caller's, or the agent's own policy from the configuration, restricted by the one given.
`Escalate` takes the same record but replaces the policy, after the user approves it with `ctx.ui.confirm`.

## Test

The tests run the extension in a real pi session with pi's faux provider in place of a model.

```sh
bun run build
node ../../vendor/pi-mono/node_modules/vitest/dist/cli.js --run
```

They need the vendored pi's dependencies, `npm ci --ignore-scripts` in `vendor/pi-mono`.
