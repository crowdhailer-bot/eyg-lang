# opencode plugin

An [opencode](https://github.com/anomalyco/opencode) plugin that adds an `eyg` tool.
Every effect performed by the agent's EYG program is decided by a policy, written in EYG.

The EYG interpreter, written in Gleam, is bundled into the plugin so no `eyg` executable is needed.
Policies are evaluated in the same process as opencode by the [`opencode_plugin`](./src/opencode_plugin.gleam) module.
The plugin itself, [`plugin/eyg.ts`](./plugin/eyg.ts), wires that module into opencode's tool, chat and session hooks.

## Build

```sh
bun run build
```

This builds the Gleam package and bundles it, with the plugin, into a single file `dist/eyg.js`.

## Install

Copy, or link, `dist/eyg.js` into `.opencode/plugins/` in a project or `~/.config/opencode/plugins/` for every project.

## Configuration

The plugin looks for configuration in order:

1. the path in the `OPENCODE_EYG_CONFIG` environment variable
2. `.opencode/eyg.eyg` in the project
3. `~/.config/opencode/eyg.eyg`

Without a configuration file the [default policy](./plugin/default.eyg) can read and change files in the project and do nothing else.
A configuration file is reloaded when it changes.

The configuration file is an EYG program that returns a record:

- `policy` a record of gate functions, one field per effect named in snake case, `ReadFile` is decided by `read_file`.
  A gate returns `Pass(lift)` to perform the effect, possibly with a changed lift, or `Mock(lower)` to resume the program without performing it.
  Effects without a field are unavailable.
  DecodeJSON, EYGParse, Flip, Hash, Random, StandardOut and StandardError are available unless the policy has a gate for them,
  output is added to the tool result. Exit and StandardIn are never available.
- `context` optional, any value, it is in scope as `context` for every program. A `readme` field is added to the system prompt.
- `agents` optional, a record of policies for opencode agents by name. An agent with a policy here uses it instead of its parent's.

File paths are made absolute before a gate sees them.
Relative imports are decided by the `read_file` gate.

The [overlay EYG package](../../eyg_packages/overlay/) has helpers for writing policies, i.e. `read_write(roots)` and `fetch_hosts(hosts)`.

```eyg
let {read_write, fetch_hosts} = import "<path to>/eyg_packages/overlay/policy.eyg"
let files = read_write(["/path/to/project"])

{
  policy: {
    read_file: files.read_file,
    read_directory: files.read_directory,
    write_file: files.write_file,
    task: Pass
  },
  agents: {
    general: {
      read_file: files.read_file,
      fetch: fetch_hosts(["api.github.com"])
    }
  }
}
```

## Subagents

Sessions keep the policy they started with.
A session without one uses its agent's policy from `agents`, otherwise its parent session's policy, the top level session uses `policy`.

Two host effects start subagents, both take `{agent: String, prompt: String, policy: {..gates}}` and return the subagent's final answer.

- `Task` the subagent's policy is the caller's, or the agent's policy from `agents`, restricted by the given policy.
  The child's gate runs first and its `Pass` value is checked by the parent's gate, effects missing from either are unavailable.
- `Escalate` the given policy replaces the caller's.
  The user is asked to approve it with the `eyg_escalate` permission, set `"permission": {"eyg_escalate": "ask"}` in `opencode.json`.

Both are only available when the policy has a `task` or `escalate` gate.

## Development

```sh
gleam test
```
