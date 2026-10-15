---
name: EYG in OpenCode
description: What changes when EYG becomes a tool, a policy boundary or the complete tool dispatcher.
date: 2026-10-15
---

# EYG in OpenCode

EYG makes an agent's actions explicit: a program asks for an effect, and its
host decides whether to perform it. This is useful only for the actions that
actually cross that boundary. Giving an agent an EYG tool alongside another
unrestricted tool does not subject that other tool to EYG's policy.

The [integration levels](../../guides/harness_policies.md#integration-levels)
separate choosing a scripting language, adding an embedded tool, applying a
policy, and routing the complete tool set through it.

There are two checked OpenCode integrations. Both use the shared Gleam runtime
and pinned v1.19.0 SDKs, with small library bindings and no vendored OpenCode tree.

The [public plugin](../../guides/opencode_plugin.md) adds an EYG tool with
computer effects. Its system-prompt hook supplies the effect signatures,
context readme, syntax and builtins. Native OpenCode tools retain their own
permissions. The guide shows a configuration that permits EYG while denying
the other tool names.

The [dispatcher integration](../../guides/opencode_dispatcher.md) wraps native
and MCP tools after OpenCode resolves them. The normal callbacks retain their
validation, permissions, hooks, metadata and abort behavior. Only mode exposes
EYG alone; Gate also exposes direct declarations, with every direct call going
through the same effect policy; Off restores the host tool set. The installer
verifies the pinned dispatcher bytes and refuses other or modified sources.

A policy field is a gate: read_file decides ReadFile, and read decides native
Read. Pass(lift) continues; Mock(reply) supplies a response without invoking the
host. Paths are absolute before gates see them. Relative imports are checked
recursively. Gates are pure, while configuration is trusted EYG that can perform
IO. The [policy guide](../../guides/harness_policies.md) defines composition and
the distinction between path decisions and filesystem confinement.

Subagents expose an important timing boundary. A child needs its assigned
policy before its first action. The public plugin calls session.create, stores
the policy, then calls session.prompt. The native integration receives Task's
child-session metadata before the child runs. Both retain that assignment on
later calls. A trusted named-agent policy supplies a starting point; Task
restricts it. The plugin's Escalate replaces it only after host approval.
Assignments live in memory and are reset when configuration changes; they are
not persisted across host restarts.

The guides link fresh recordings. The plugin check uses the official SDK with
a deterministic fetch service. The dispatcher check executes the actual
patched upstream resolve function with official AI SDK and Effect libraries,
plus deterministic application services. They establish the adapter behavior;
they make no live inference call and do not claim a full OpenCode UI run.

This preserves the useful conclusion of the earlier experiment: public plugin
hooks can add a policy-aware tool, while complete routing needs access to the
host's dispatcher. The two installation paths make that boundary visible.
