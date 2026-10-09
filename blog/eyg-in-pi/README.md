---
name: EYG in pi
description: Make EYG the only way a pi agent acts, without changing pi, and what pi-agent-core offers an in-browser overlay.
---

# EYG in pi

The [opencode post](../eyg-in-opencode/README.md) needed a change to opencode itself to reach level 4, where EYG is the agent's only tool and every other tool is an effect.
[Pi](https://pi.dev) gets there with an extension and no change to pi.

Pi is split into packages.
[`pi-agent-core`](../../vendor/pi-mono/packages/agent/) is a stateful agent loop with tool execution and event streaming, built on [`pi-ai`](../../vendor/pi-mono/packages/ai/), a model API over many providers.
The pi coding agent is built on them, it adds the terminal UI, sessions, extensions and the built-in tools `read`, `bash`, `edit` and `write`.
Pi is vendored in [`vendor/pi-mono`](../../vendor/pi-mono/), added in one commit, `vendor pi as is`, from upstream `main` at `6fb2e78`, unchanged; its git tree hash is the same as upstream's. Nothing in pi is changed after that commit.
Opencode is vendored the same way next to it, with the [opencode post's](../eyg-in-opencode/README.md) changes as the commits that follow.

| Level | What | How in pi |
| --- | --- | --- |
| 1 | The agent can only script in EYG. | An extension blocks every `bash` command except `eyg`. |
| 2 | EYG is a tool. | The [extension](../../packages/pi_extension/) adds an `eyg` tool, the interpreter is bundled. |
| 3 | Every program is checked by a policy, subagents keep it. | A policy in `.pi/eyg.eyg` gates every effect, including pi's own tools. |
| 3.a | Subagents can have other policies, more restrictive or approved by the user. | `Task` and `Escalate` start in-process pi-agent-core agents. |
| 4 | EYG is the only tool, everything else is an effect. | `--eyg-only`, pi's tools stay callable but are not declared to the model. |

## With pi-agent-core alone, level 4 is the default

`pi-agent-core` has no built-in tools.
An application gives an `Agent` its tools, so an agent whose only tool is `eyg` is level 4 by construction:

```typescript
const agent = new Agent({
  initialState: { systemPrompt, model, tools: [eygTool(policy)] },
  streamFn: models.streamSimple.bind(models),
});
await agent.prompt("Summarise the open issues");
```

Its `beforeToolCall` hook could check calls against a policy, but with one tool the policy belongs in the EYG runtime, where each effect is seen.
This is how the extension's subagents work.

## Install

```sh
git clone https://github.com/CrowdHailer/eyg-lang.git
cd eyg-lang/packages/pi_extension
bun run build
mkdir -p ~/.pi/agent/extensions/eyg
cp dist/index.js ~/.pi/agent/extensions/eyg/index.js
```

Or load it once with `pi -e path/to/dist/index.js`.
The bundle is the extension and the Gleam EYG runtime, pi supplies `pi-agent-core`, `pi-ai` and TypeBox to extensions.

## Level 1

Pi has no permission rules, it runs tools with the permissions of its process.
Level 1 is a `tool_call` handler, [`bash-only-eyg.ts`](../../packages/pi_extension/src/bash-only-eyg.ts):

```typescript
pi.on("tool_call", async (event) => {
  if (event.toolName !== "bash") return undefined
  const command = String(event.input.command ?? "").trim()
  if (/^eyg(\s|$)/.test(command) && !/[;&|`$<>\n]/.test(command.replace(/'[^']*'/g, "''"))) return undefined
  return { block: true, reason: "Only the eyg command can be run, write a program with `eyg run -c '<code>'`." }
})
```

As in opencode the shell is gone but the `eyg` CLI performs every effect a program asks for, there is no policy.

## Levels 2 and 3

The `eyg` tool runs EYG programs with the same runtime and configuration as the opencode plugin.
Without configuration the default policy can read and change files in the working directory and nothing else.
A policy is an EYG record of gates, read from `.pi/eyg.eyg`, `~/.pi/agent/eyg.eyg` or `PI_EYG_CONFIG`.

```eyg
{
  policy: {
    read: Pass,
    write: (args) -> {
      match !string_ends_with(args.path, "notes.md") {
        True(_) -> { Pass(args) }
        False(_) -> { Mock(Error("only notes.md can be written")) }
      }
    },
    task: Pass
  },
  context: {readme: "A test project."}
}
```

The difference from opencode is that pi's tools are effects at every level, not only at level 4.
A tool can run another tool with `ctx.executeTool(name, args)`, through pi's validation, `tool_call` and `tool_result` hooks and events,
so `perform Read({path: "fruit.txt"})` runs pi's own `read`, and is decided by the `read` gate first.
`bash` has no gate in the policy above, so `perform Bash({command: "ls"})` fails with "The effect Bash is not allowed by your policy, it has no `bash` gate."

The tool's description lists the effects the policy allows, with types from each tool's schema, and EYG's syntax guide.
It is built by the tool's `prepareLoadout` hook, which pi runs whenever the active tools change.

## Level 3.a, subagents

Pi has no subagents of its own, its example extension starts a separate `pi` process for each.
The extension does not need to: `Task({agent, prompt, policy})` starts an in-process `pi-agent-core` `Agent`,
using the session's model through `ctx.modelRegistry.streamSimple`, whose only tool is `eyg`.

- `Task` restricts, the subagent's policy is the caller's, or the agent's own from `agents` in the configuration, with the given policy applied first.
- `Escalate` replaces the policy, after the user approves it in a dialog that shows the agent, the effects and the prompt (`ctx.ui.confirm`).
  Without a UI, in print or JSON mode, an escalation is refused.

The subagent's effects on pi's tools run through the parent's `ctx.executeTool`, so they appear as nested calls of the parent's `eyg` call,
and the subagent's model usage is added to the `eyg` tool result so the session's totals stay right.

## Level 4

`pi --eyg-only`, or `PI_EYG_ONLY=1`, gives the model only `eyg`.
Pi's tools stay active, so `ctx.executeTool` can still call them, but the `eyg` tool's `prepareLoadout` returns them as `hiddenDeclarations`, leaving them out of requests.
This is the mechanism pi's own `codemode` tool uses for its `codemode.mode: "only"` setting, an extension can do the same under another name.

## How it was checked

The extension's [tests](../../packages/pi_extension/test/eyg.test.ts) run it in a real pi session, with pi's faux provider in place of a model:

1. pi's `read` and `write` performed from EYG, a `write` outside `notes.md` mocked by the policy and the file unchanged, `bash` refused.
1. `edit` with `edits: [{old_text, new_text}]` changes the file, the nested fields mapped back to `oldText` and `newText`.
1. The tool description lists `Read` and `Task` but not `Bash`, and the configuration's readme.
1. With `PI_EYG_ONLY=1` the request declares exactly `["eyg"]` and `perform Read` still reads the file.
1. A `Task` subagent is sent only `eyg`, can read, and cannot write although its parent can.
1. The level 1 extension blocks `curl` and `eyg ... && curl`, and allows a single `eyg run`.

There is no recording with a real model.
This machine has no model credentials, OpenCode Zen's free models only serve opencode,
and the anonymous LLM7 tier's daily token limit had run out for every model by the time pi sent its first request.
The recording for opencode used OpenCode Zen's free Big Pickle model, which pi cannot use.

## What made it easy, and what is still hard

Each of the opencode plugin's difficulties has an answer in pi's extension API.

| opencode plugin | pi extension |
| --- | --- |
| A plugin cannot call other tools. | `ctx.executeTool()` and `ctx.tools`. |
| A tool's description is the same for every session. | `prepareLoadout` returns descriptions for the current loadout. |
| Hiding tools is a permission, and Zen's free tier needs `bash` and `read`. | `hiddenDeclarations` keeps tools callable but undeclared. |
| Subagents are separate sessions a plugin cannot attach a policy to. | `pi-agent-core` agents run in process with whatever tools the extension gives them. |
| The approval dialog shows only the permission name. | `ctx.ui.confirm(title, message)` shows the agent, effects and prompt. |

What remains:

1. **Inactive tools are not callable.**
   A built-in tool with `direct` exposure is only callable while active, so level 4 keeps every tool active and hides its declaration.
   Starting pi with `--tools eyg` would leave nothing to call.
2. **Subagents are not sessions.**
   An in-process subagent has no transcript entry of its own, it is not in `/tree`, cannot be resumed, and its tool calls are recorded only as the parent's bounded `nestedCalls`.
   Pi's `pi-durable` package has child tasks with storage, a durable version could use them.
3. **Policies are not persisted.**
   A policy is a value with EYG functions, kept in memory.
   `pi.appendEntry()` could store the policy's source, or the hash of its IR, to rebuild it on resume.
4. **The description is refreshed when tools change.**
   `prepareLoadout` runs when the active tools change, an edited policy file is used by the next program at once, but the description follows on the next loadout change or `/reload`.
5. **Level 1 is a regular expression.**
   Pi parses no shell, so the level 1 extension refuses anything with shell syntax outside single quotes.
6. **Names and types.**
   EYG fields are snake case, so `edit`'s `edits: [{oldText, newText}]` is written `edits: [{old_text, new_text}]` and mapped back through the tool's schema, nested arrays included.
   Results with `structuredContent` (`bash`, `read`) come back as EYG records with snake case fields.

## What pi-agent-core and pi offer that overlay does not yet do

[Overlay](../../packages/overlay/) has one tool, `run`, and its agent loop is written separately in the CLI and the web state machine.

**pi-agent-core**

1. An agent loop as a library, independent of any interface, used by the TUI, print, JSON and RPC modes and the SDK alike.
2. Fine-grained events: agent, turn, message start, update and end with streaming deltas, and tool start, progress and end.
3. Steering and follow-up queues, to add messages while the agent is working or after it would stop.
4. Parallel tool calls, with a per-tool sequential override.
5. `beforeToolCall` and `afterToolCall` hooks that can block a call, rewrite a result or end the run.
6. `prepareRequest` and `finishTurn`, to rebuild the context before every request and force or stop a continuation.
7. Custom message types in the transcript, with `convertToLlm` and `transformContext` to filter, prune or inject before each request.
8. A transcript that owns the system prompt and tool declarations, changed mid-conversation with system messages.
9. Unified thinking levels, `off` to `max`, with token budgets.
10. `continue()` from an existing transcript, `abort()` and `waitForIdle()`.
11. `streamProxy` for browser apps that keep keys on a server.

**pi-ai**

12. Over forty providers, a model catalog updated from pi.dev, and providers added at runtime.
13. Credential stores, auth resolution and OAuth logins.
14. Token and cost tracking, prompt-cache lifetimes and cache warming.
15. Handing a conversation to a different provider mid-session, and serialising contexts.
16. Constrained sampling for tool arguments, partial JSON while tool calls stream, and argument validation.
17. Image generation and classifier models.
18. A faux provider for deterministic tests, used for this post.
19. Browser-safe bundles, checked in CI by bundling the public entry points for the browser.

**The rest of pi**

20. `pi-codemode`, JavaScript in a QuickJS WebAssembly sandbox whose only capability is calling injected tools.
21. `pi-mcp`, a small MCP client with stdio and HTTP transports and OAuth.
22. `pi-durable`, an agent harness that commits every turn before showing it and resumes after a crash, with child tasks and task graphs, on SQLite, JSONL or Cloudflare Durable Objects.
23. `pi-env`, running an agent's tools on another machine over SSH.
24. `pi-protocol`, `pi-client` and `pi-server`, several clients attached to one session.
25. `pi-evals`, behavioural evals of the coding agent.
26. `pi-tui`, a terminal UI framework with differential rendering.
27. The coding agent's extensions: tools, commands, shortcuts, flags, providers, renderers and custom terminal components.
28. Skills, prompt templates, themes and packages installed from npm or git.
29. Sessions as trees: branching, forking, cloning and compaction.
30. Print, JSON and RPC modes, and an SDK.
31. Project trust before loading a project's extensions and settings.
32. `/export` to HTML or JSONL and `/share` to a gist or a Radius artifact.
33. Virtual models that route each request, and llama.cpp integration.
34. Images in prompts and in tool results, resized to the limits of each model.
35. Tool exposure levels, `direct`, `model-only`, `codemode`, `deferred` and `hidden`, tool namespaces, MCP tool annotations, and tool search for tools not listed to the model.
36. Tools that call other tools with `ctx.executeTool`, through the same hooks, recorded as nested calls of the caller.
37. Extension dialogs forwarded to RPC clients.
38. `pi-telemetry`, vendor-neutral telemetry contracts, and `chord`, a runtime for composing applications from plugins.
39. Bug reports with environment and diagnostics, uploaded or exported as a zip.

Overlay has a policy deciding every effect, typed configuration, a REPL and structural editor, isolated artifacts and evals that grade the program's value, none of which pi has.

## An in-browser overlay on pi-agent-core

The browser overlay on the `overlay-tui` branch (`overlay_web` and `overlay_public`) runs its own agent loop in a Lustre state machine.
Replacing that loop with `pi-agent-core` would bring the features above.
What is already there:

- `pi-agent-core`, `pi-ai`, `pi-client` and `pi-protocol` bundle for the browser, CI checks it.
- Providers take an explicit `apiKey`, or a `CredentialStore` such as one backed by local storage.
- `streamProxy` sends requests through a server that holds the key.
- `pi-durable`'s SQLite and JSONL cores run without Node, given a database or file system facade.

What is needed:

1. **An `eyg` tool over browser effects.**
   The runtime used by the plugins is built on `loam`, which reads files with Node.
   The browser needs the same policy runtime over EYG's browser harness (`touch_grass/harness/browser`, Fetch, Alert, Copy, Download, Visit and the rest) and overlay's `Artifact` and `Show`.
   `overlay_web` already runs EYG with a policy in the browser, its run tool would become an `AgentTool`.
2. **Bindings from Gleam.** Overlay's frontend is Gleam and Lustre, `Agent` is a TypeScript class.
   It needs FFI bindings for creating an agent, prompting, aborting and subscribing to events, with events decoded into overlay's messages.
3. **Provider access.** Ollama Cloud does not allow browser CORS requests, overlay_public proxies it. Pointing pi-ai's Ollama provider at that proxy, or using `streamProxy`, keeps that. Bedrock and OAuth logins are Node only.
4. **Session storage.** pi-agent-core keeps state in memory. Durable sessions in the browser need an IndexedDB or OPFS facade for pi-durable's storage, which pi does not provide.
5. **A UI.** Pi's own browser components, `pi-web-ui`, were removed from the repository on 2026-05-20. The last release, 0.75.3, depends on pi-ai 0.75, before pi's 1.x API, so it cannot be used with the current agent. Overlay keeps its own UI.
6. **Artifacts.** Keep overlay's, see below.

## Origin isolated artifacts

Pi does not have them.
The current repository has no artifact concept for executable content.

`pi-web-ui`, before its removal, had an artifacts panel for HTML, SVG, Markdown and documents.
HTML ran in a `srcdoc` iframe with `sandbox="allow-scripts allow-modals"` and no `allow-same-origin`, so each artifact had an opaque origin and could not read the app's storage or DOM.
But no content security policy was injected, so an artifact could make network requests,
and runtime providers gave it a `postMessage` bridge back to the app to list, read and write other artifacts and attachments.
In a browser extension the iframe loaded a packaged `sandbox.html` instead.

`/share` uploads a session transcript as a "Radius artifact" with organisation visibility, or to a GitHub gist.
These are records of a session, not executable artifacts, and the Radius service is hosted outside the repository.

Overlay's artifacts on the `overlay-tui` branch are more isolated:
a trusted wrapper frame and the artifact frame are both `srcdoc` with `sandbox="allow-scripts"` and distinct opaque origins,
the wrapper's CSP denies every connection, worker, object, base URL, form action and nested frame,
artifacts have no bridge to overlay, and versions are shared through the hub at a link with no index.
Neither overlay nor pi gives an artifact its own stable origin, for example a subdomain per artifact, so an artifact cannot keep storage of its own.
