---
name: Artifact control that cleans up after itself
description: Repeated browser actions now release their reply listeners, including when a preview stops responding.
date: 2026-10-04
---

# Keep building. Leave fewer things running.

An Overlay session can build a page, fill its forms, inspect the result and try
again. Those small actions should finish when their work is done.

Artifact control now removes its reply listener after every completed request.
It also removes the listener when a preview misses its deadline. Previously,
each request left a callback attached to the application window for the rest
of the page's lifetime. The callback stopped being useful, but every later
message still reached it.

The change keeps that work bounded as a session grows. It does not change the
Puppet API, the artifact sandbox or the results a program receives. A missing
preview still returns a readable error, so the agent can decide what to try next.

Two browser regressions guard the lifecycle: twenty consecutive controls return
the listener count to its starting value, and a frame that never replies does
the same after its deadline. They exercise the real browser transport, including
the timeout path.

The reusable browser binding lives in Plinth. Overlay uses it to close the loop:
register, wait, release. There is no new EYG effect and no configuration to change.

This is a resource-lifecycle improvement, not a measured claim about frame rate
or memory savings. It removes a known source of accumulating work so longer
artifact sessions have less to carry.
