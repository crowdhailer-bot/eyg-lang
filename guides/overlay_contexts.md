---
name: Overlay contexts
description: Find existing libraries and guides before an agent writes a program.
---

# Overlay contexts

The librarian context provides a pure, ranked catalogue of packages and guides.
From the repository root:

```sh
eyg eval -c 'let context = import "./eyg_packages/overlay_librarian/index.eyg" context.libraries.search("parse json")'
```

The first result is the JSON package, with its reference, summary and example.
`context.guides.search(query)` searches guides; `context.guides.read(slug)`
fetches Markdown through the existing Fetch effect, returning Ok(text) or an
error. A policy can restrict that fetch like any other request.

Share the context with `eyg share eyg_packages/overlay_librarian/index.eyg`,
then open `/overlay/?reference=<cid>`. Its readme becomes part of the agent's
instructions and its functions are available as `context`.

Catalogue names such as @json select the latest package for exploration. Pin the
version and CID before sharing a program that uses one. Catalogue tests check
that every listed package and guide exists and that every guide is listed.

The [recording](../packages/tracing/recordings/overlay-librarian.mp4) executes the
local search, then finds the syntax guide with `context.guides.search("write
match expression")`. Recheck it from `packages/tracing` with
`EYG_BIN=/absolute/path/to/eyg gleam run -m tracing/context_demo`.
