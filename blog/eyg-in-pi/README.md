---
name: EYG in Pi and the browser boundary
description: Policy-aware native tools, in-process subagents and the remaining work for a browser agent loop.
date: 2026-10-15
---

# EYG in Pi and the browser boundary

The [Pi extension](../../guides/pi_extension.md) exposes Pi 1.2.0 tools as EYG
effects without changing Pi. Its runtime, configuration, argument mapping and
tooling are Gleam. Pinned official SDK packages supply the native agent loop
and tools; the repository contains no vendored Pi source tree.

Pi's callable tools and its model-facing declarations are separate. The
extension uses ctx.executeTool to retain validation, hooks and events. With
--eyg-only, hiddenDeclarations removes other tools from model requests while
keeping them callable through EYG. Inactive tools are unavailable to that
dispatcher, so selecting only EYG as the active tool set would remove its
underlying operations too.

A program can perform Read, Write or Edit using snake case arguments. The
adapter follows the native schema through nested records and arrays, including
old_text/new_text edits. Paths are normalized before gates run. A Mock reply
leaves the native operation uncalled. The model's description lists the effects
its policy permits and includes language guidance.

Task starts an in-process pi-agent-core Agent with EYG as its only tool. Its
closure retains the restricted policy for every call. Nested token usage,
cache usage and cost vectors are added to the outer result. Escalate requires
an interactive approval; a missing UI or refusal starts no child. Abort signals
are forwarded and listeners are removed afterward.

These children are not durable Pi child sessions. They do not independently
appear in the session tree or resume after restart. Policy values contain EYG
functions and remain in memory. Persistence would need a portable policy source
or IR reference together with a durable session record. The tool description
refreshes with the loadout; execution reads changed configuration immediately.

The guide's checked video uses actual SDK sessions, native file tools and a
scripted provider. It verifies denial, nested edits, hidden declarations,
restricted children and usage reporting. It makes no live model call. The
optional shell-only adapter is a separate earlier integration level; it does
not supply the extension's per-effect policy boundary.

## A browser agent loop is a separate experiment

The installed pi-agent-core library provides event streaming, transcript
transformation, tool hooks, request preparation, continuation and cancellation.
The extension already uses that loop for its children. Replacing Overlay's
browser session engine with it has not been implemented or measured here.

A useful experiment would keep Overlay's UI and adapt one typed EYG tool to
the agent loop. It needs browser-specific handlers for Fetch, Download, Visit,
Artifact and Show rather than the computer runtime's Node file operations.
Gleam library bindings would decode agent events into the UI's messages. A
server-held credential broker, browser session storage, cancellation and replay
would each need explicit ownership. Existing Node extensions and durable stores
should not be assumed to work in the browser unchanged.

Keep [Overlay's artifact boundary](../../guides/overlay_artifacts.md) independent
of that choice. Executable previews use opaque-origin frames, restrictive CSP
and bundled resources. They receive no capability to act on the host or read
application storage. Sharing a transcript is a different operation from hosting
an executable preview. Stable per-artifact storage or a host bridge would add
new capabilities and needs a separate design; swapping the agent loop supplies
neither.
