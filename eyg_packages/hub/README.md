# hub

A context for looking at what is published on the EYG hub.

```
https://eyg.run/overlay?package=hub
```

The module is a record with a `readme`, which is what makes it a context.

## Public API

| Helper                                | What it does                                                     |
| ------------------------------------- | ---------------------------------------------------------------- |
| `packages({})`                        | One row per package, the newest release of each.                  |
| `releases({})`                        | Every release the hub has, oldest first.                          |
| `search({text})`                      | Packages whose name contains the text, either case.               |
| `history({package})`                  | Every release of one package.                                     |
| `table({title, headings, rows})`      | Builds an HTML table to write and open in a window.               |

A release is `{package, version, module}`, where `module` is the content id.

## How it reads the hub

`GET /packages/pull` returns the ledger of everything published. Each entry
carries its release as a JSON payload inside the entry, so it is decoded in two
passes. Every call reads the whole ledger, which is why the readme tells the
agent to read once and filter the result.

Signatures on entries are not checked here. This context is for looking, and a
module fetched by content id is verified by its hash anyway.
