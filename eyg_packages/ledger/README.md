# ledger

Everything to do with the data an EYG hub keeps: reading the two ledgers,
finding out who owns a package name, and signing and submitting a release.

```eyg
let ledger = @ledger

// what the hub has
ledger.packages({})
ledger.history({package: "standard"})
ledger.owner({package: "standard"})

// publishing a new release of it
ledger.publish({key, key_id, signatory, chain, package: "standard", module})
```

The fields at the top level are bound to `eyg.run`. `at`, `https` and `http`
bind the same functions to another hub, which is how a hub running on this
machine is reached.

```eyg
let local = @ledger.http({host: "localhost", port: 8080})
local.packages({})
```

## Reading

| Function                  | Answers                                                                    |
|---------------------------|----------------------------------------------------------------------------|
| `releases({})`            | every release, oldest first, each with its signatory, chain, cid and sequence |
| `packages({})`            | one row per package, the newest release of each                            |
| `history({package})`      | every release of one package, oldest first                                 |
| `latest({package})`       | `{package, version, module, published}`, the newest release of one package |
| `signatories({})`         | every signatory the hub knows, with the key events recorded against it     |
| `publishers({package})`   | who has released under a name                                              |
| `owner({package})`        | `Some({package, signatory})` or `None({})`, who the hub says owns a name   |

`publishers` is history and `owner` is permission. Someone can own a name
nobody has released under, and the two answers can disagree.

## Publishing

| Function        | Does                                                                    |
|-----------------|-------------------------------------------------------------------------|
| `next({chain})` | the `{sequence, previous}` a new entry in a chain must carry             |
| `entry({..})`   | the bytes of a release entry, which is what gets signed                 |
| `publish({..})` | works out `next`, builds the entry, performs `Sign`, and submits it     |

A chain is per publisher, not per package, so a release follows whatever that
signatory published last.

The entry bytes are DAG-JSON with the keys of every object sorted. Getting that
wrong signs the wrong bytes and the hub rejects the entry, so `test.eyg` checks
them byte for byte against what the Gleam encoder produces.

Signing performs the `Sign` effect, so the key never leaves whatever holds it.
In a browser that is the browser.

## Tests

```sh
eyg script entry.eyg
```

Every function is covered with the hub answered by a handler, including the
signature the hub is sent and the failures it can return.
