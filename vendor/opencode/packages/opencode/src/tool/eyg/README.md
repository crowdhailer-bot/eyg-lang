# EYG

In this copy of opencode [EYG](https://eyg.run) is the only tool.
Every other tool, built in, from a plugin or from an MCP server, is an effect that an EYG program performs,
i.e. `perform Read({file_path: "README.md"})`, and every effect is decided by the user's policy.

`OPENCODE_EYG` sets the mode:

- `only`, the default, the model is given only the `eyg` tool.
- `gate` opencode's tools are also given to the model, a call to one runs the program `perform Tool(args)` so it is decided by the same policy.
  Use this with providers that require opencode's usual tools, such as the free models of OpenCode Zen.
- `off` opencode's usual tools and no EYG.

## Policies

The policy is read from `OPENCODE_EYG_CONFIG`, `.opencode/eyg.eyg` or `~/.config/opencode/eyg.eyg`, otherwise [`default.eyg`](./default.eyg) is used.
The configuration is described in the [opencode plugin](https://github.com/CrowdHailer/eyg-lang/tree/main/packages/opencode_plugin), which shares its runtime.
A policy field is the snake case of the effect, the `apply_patch` tool is the effect `ApplyPatch` decided by `apply_patch`.
Fields of a tool's arguments are snake case in EYG, `filePath` is `file_path`.

`Task` takes an extra `policy` field, the subagent's policy is the caller's, or the agent's own from the configuration, restricted by it.

## Runtime

`runtime.js` is `dist/core.js` built by `bun run build` in `packages/opencode_plugin` of [eyg-lang](https://github.com/CrowdHailer/eyg-lang).
`syntax.md` and `builtins.md` are copies of the syntax and builtins guides from the same repository, they are included in the tool description.
