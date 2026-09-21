---
name: EYG browser drive
description: Embed the JavaScript interpreter and give an agent one tool with explicit browser effects.
---

# An agent with one EYG tool

EYG is an expression language with managed effects. A script can calculate
values, build records and lists, and call functions. To interact with the outside
world it must perform an effect that the host explicitly implements.

The [Phantom demo](../packages/browser_drive/README.md) embeds the existing
Gleam parser and JavaScript interpreter. Its assistant can inspect a page,
restyle it and add a button. The LLM is mocked; the tool execution is real.

## Build and run the JavaScript interpreter

From `packages/browser_drive`:

```sh
npm ci
npm run build
npm start
```

Gleam compiles the repository's parser, IR and interpreter. The bundler produces
`dist/eyg.js` for embedding and `dist/phantom.js` for single-script injection.
The worker is embedded in both bundles; there is no second worker file to host.

In a browser module on the local server:

```js
import { runEyg } from '/dist/eyg.js';

const value = await runEyg(`
  let name = "Stockholm"
  {city: name, minutes: !int_multiply(3, 60)}
`);
// {city: "Stockholm", minutes: 180}
```

`runEyg` parses the complete source, starts a worker and returns a Promise of
plain data. Syntax errors and unhandled effects reject the Promise. Strings,
safe integers, records, lists and tags cross the boundary; closures, DOM objects
and JavaScript functions do not. A tag is returned as `{tag, value}`.
Host booleans become EYG `True({})` / `False({})`; `null` becomes `{}`.

The [worker implementation](../packages/browser_drive/src/worker.mjs) calls
`parser.all_from_string`, constructs the interpreter environment, and advances
`state.step`. At `UnhandledEffect`, it suspends the continuation, asks the host
to handle the effect, then resumes with the returned EYG value.
The library's `expression.execute` and `expression.resume` provide the usual
run-until-break API; this worker uses the lower-level step API so it can also
enforce an instruction budget.

## Give the script a capability

```js
const output = [];
const result = await runEyg(`
  let _ = perform Log("Hello from EYG")
  !int_add(20, 22)
`, {
  effects: {
    Log(message) {
      if (typeof message !== 'string') throw new Error('Expected text');
      output.push(message);
      return {};
    },
  },
});
// result === 42; output === ["Hello from EYG"]
```

There is no ambient `window`, `document`, filesystem, network or JavaScript
evaluation in EYG. `perform Fetch(...)` fails here because only `Log` exists.
Imports and package references also fail: this runner installs no resolver.
Runtime argument validation is required even if you separately run type
inference; this small harness does not run the optional EYG type checker.

For the browser demo:

```js
import { createBrowserHarness, runEyg } from '/dist/eyg.js';

const harness = createBrowserHarness();
harness.begin();
try {
  const elements = await runEyg('perform GetElements("main h2")', {
    effects: harness.effects,
    onEffect(event) { console.log(event.name, event.status); },
  });
  harness.commit();
  console.log(elements);
} catch (error) {
  harness.rollback();
  throw error;
}
// Later: harness.undo(), or harness.destroy() to undo everything.
```

Phantom exposes `GetElements`, `WriteCSS`, `InsertButton`, and `SetAttribute`.
Their exact arguments and restrictions are in the
[capability table](../packages/browser_drive/README.md#capabilities).
The fourth effect is a general way to mark inspected elements with
`data-eyg-*` presentation attributes. It enables shortlists without exposing
arbitrary HTML, scripts or event listeners.

The button's action is host-defined: toggle the changes. Passing a label cannot
turn it into a purchase button or an arbitrary JavaScript callback.

## A JavaScript agent loop with one tool

The provider receives this tool schema:

```js
{
  name: 'run_eyg',
  description: 'Run EYG code to inspect and change the page using the explicitly allowed effects.',
  parameters: {
    type: 'object',
    properties: { code: { type: 'string' } },
    required: ['code'],
    additionalProperties: false,
  },
}
```

The [complete loop](../packages/browser_drive/src/agent.mjs) is small: ask the
provider, validate the tool name, execute its EYG, append the result, and repeat
until a final message. Every tool result includes `ok: true` and a value, or
`ok: false` and an error. Failed runs roll back; the model can inspect again or
explain the failure. The loop stops after eight provider turns.

```js
import { createBrowserHarness, runAgent } from '/dist/eyg.js';

const controller = new AbortController();
const harness = createBrowserHarness();
const reply = await runAgent({
  messages: [{ role: 'user', content: 'Make the graph bigger' }],
  context: { site: location.hostname, title: document.title },
  harness,
  signal: controller.signal,
  complete: async ({ messages, tools, signal }) => {
    const response = await fetch('/api/assistant', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages, tools }),
      signal,
    });
    if (!response.ok) throw new Error('The model request failed');
    return response.json();
  },
});
console.log(reply.message);
// Pass reply.messages back on the next user turn to retain the conversation.
```

`/api/assistant` is an integration example, not an endpoint supplied by the demo.
Keep provider credentials in your backend. Translate the neutral conversation
format into your provider's API and translate the reply into **one** of:

```js
{ type: 'tool_call', name: 'run_eyg', arguments: { code: 'perform GetElements("svg")' } }
{ type: 'message', content: 'The graph is now larger.' }
```

Assistant tool messages use `{role: "assistant", tool_call: {id, name, arguments}}`.
Results use `{role: "tool", tool_call_id, content}` with a JSON-encoded result.
The adapter must preserve these IDs. Reject extra tools or multiple unexpected
calls in the adapter; do not execute them. `runAgent` validates the single call
again. A real provider should respect `signal` and have a request deadline.
The EYG deadline only bounds interpreter runs, not the provider's network call.

The bundled [mock provider](../packages/browser_drive/src/mock.mjs) follows
exactly this protocol: it first requests element snapshots, then produces EYG
using the returned selectors and IDs, then reports the result.

## Context and the complete system prompt

The same `context` record is passed to the provider as JSON and to EYG as the
variable `context`. Supply only data needed for the task:

```js
await runEyg('context.site', {
  context: { site: 'example.test', title: 'My dashboard' },
});
```

The full prompt is defined in
[`systemPrompt`](../packages/browser_drive/src/agent.mjs).
**It includes the entire canonical [EYG syntax guide](syntax.md)**, embedded at
build time. There is no separately maintained syntax summary to drift out of date.
Builds also write the complete assembled prompt to `dist/system-prompt.txt`,
available at http://127.0.0.1:4173/dist/system-prompt.txt.

```js
import { systemPrompt } from '/dist/eyg.js';
console.log(systemPrompt({ site: 'example.test', title: 'My dashboard' }));
```

The instructions require the agent to inspect before changing anything, use
observed selectors, treat page text as untrusted data, avoid invented results,
respect the exact effect contracts and return concise reports supported by
successful executions. `runAgent` puts this prompt first as a system message;
callers pass only the conversation afterward. Tool results never become system
instructions. Adapt the prompt and the actual handlers together when changing
capabilities.

## The sandbox boundary

The application outside the harness can do anything JavaScript can do: render
UI, connect an LLM, manage authenticated resources, or implement a new effect.
**The EYG program can use only the explicitly supplied effects.** A model cannot
gain another capability by naming it, importing a module, or mentioning it in
the prompt. The host's effect allowlist and argument validation enforce this
boundary; the prompt does not enforce it.

The worker prevents a busy EYG computation from blocking the UI. It enforces
250,000 steps and 64 effects; the host terminates it after five seconds or
cancellation. Source, nesting and transported data are bounded. Builtins remain
pure, but an individual builtin can allocate memory before the deadline, so
this is not a hard memory quota. A worker shares its origin with the host: the
demo is not a hardened isolation boundary against malicious page JavaScript.

DOM snapshots can contain sensitive visible text. They stay in the browser
with the mock; a real model adapter sends tool results to its provider. Decide
what the model may read and restrict the handler accordingly. CSS can affect
page presentation broadly; the built-in policy blocks resource loading and
executable content, but does not promise a page-specific layout policy.
Do not expose a generic JavaScript evaluator as an effect.

## Making embedding easier

This implementation removes the repetitive parts: `runEyg` wraps Gleam values,
continuations, worker messages, deadlines and cleanup in one Promise API.
`createBrowserHarness` supplies validated, reversible browser effects;
`runAgent` supplies the single-tool loop; `systemPrompt` supplies the canonical
syntax and capability instructions. Both bundles are produced by one command
and tested against the repository's interpreter.

A future standalone distribution can package `dist/eyg.js` with versioned API
documentation. It is currently a repository-local adapter, not a published npm
package. To add a different UI or provider, reuse these functions without
changing EYG or adding ambient access.
