# hub

A context for looking at what is published on the EYG hub. The link below works
once the package has been published.

```
https://eyg.run/overlay?package=hub
```

The module is a record with a `readme`, which is what makes it a context. The
readme is the agent's instructions, and the module is in scope, as `context`,
for every program the agent writes.

## Public API

| Helper                | What it does                                                  |
| --------------------- | ------------------------------------------------------------- |
| `packages({})`        | One row per package, the newest release of each.               |
| `releases({})`        | Every release the hub has, oldest first.                       |
| `history({package})`  | Every release of one package.                                  |
| `search({text})`      | Packages whose name contains the text, either case.            |
| `at({scheme, host, port})` | The same four functions bound to another hub.             |

A release is `{package, version, module, signatory, chain, cid, sequence}`.
`module` is the content id of the code, `cid` identifies the ledger entry rather
than the module, and `chain` is the publisher's entry chain.

The top-level fields are bound to `eyg.run`. `at` binds them elsewhere, which is
how a hub running on this machine is reached.

```eyg
let local = hub.at({scheme: HTTP({}), host: "localhost", port: Some(8080)})
local.packages({})
```

## How it reads the hub

`/packages/pull` is paginated. Every read pulls the whole ledger, a page at a
time, until a short page ends it; a cursor that does not advance is reported
rather than followed forever. That is why the readme tells the agent to read
once and filter the result rather than asking again per package.

An entry whose payload this cannot read is skipped, so a ledger that grows a new
kind of entry can still be read for its releases.

Signatures on entries are not checked. This context is for looking, and a module
fetched by content id is verified by its hash anyway.

## Tests

```sh
eyg script eyg_packages/hub/entry.eyg
```

Every function is covered with `Fetch` answered by a handler, so the tests never
touch the network.
