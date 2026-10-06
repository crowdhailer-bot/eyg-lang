---
name: Overlay agents only run EYG
description: Overlay agents do all their work by evaluating EYG code, harnesses do not add tools or commands for it.
date: 2026-10-06
---

An Overlay agent has one tool, `run`, and does all its work by evaluating EYG
code. This includes reading guides and finding or fetching packages, so every
action goes through the same effects, type checks and policy.

Do not add harness tools, such as a guide tool, or CLI commands, such as one
to list published packages, for an agent to use. Write that functionality in
EYG instead.

An `@eyg` package will provide reading guides and fetching packages from EYG
code.
