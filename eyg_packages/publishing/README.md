# publishing

A context that knows what the hub has of itself, and tells you how a new
version gets there.

```
https://eyg.run/overlay?package=publishing
```

## Public API

| Helper                  | What it does                                                          |
| ----------------------- | --------------------------------------------------------------------- |
| `self({})`              | `{package, version, module, published}` for this package.             |
| `releases({})`          | Every release with the signatory that made it.                        |
| `signatories({})`       | Every signatory and its key events.                                   |
| `publishers({package})` | The signatories that have released under a name.                      |
| `owner({package})`      | The signatory the hub says owns a name, `None` if nobody does.        |
| `entry({..})`           | The exact bytes a signatory signs to publish a release.               |
| `next({chain})`         | The sequence and previous a new entry in a chain must carry.          |
| `publish({..})`         | Signs a release and submits it to the hub.                            |

## History and permission are different questions

Both hub ledgers are public, so `publishers` answers who *has* released under a
name. `GET /packages/<name>/owner` answers who is *allowed* to, and `owner`
reads it. A name nobody has been granted answers `None`, which means nobody may
publish it yet rather than that anybody may.

## Publishing

`publish` does the whole thing from a page: `next` reads the chain for the
sequence and previous, `entry` builds the bytes, `Sign` signs them and the
entry is posted to `/packages/submit` with the signature base32 encoded in the
authorization header.

Three things are checked rather than assumed, because each one fails silently:

- `entry` is compared byte for byte against the Gleam encoder. DAG-JSON sorts
  the keys of every object, so the field order is not the one the Gleam record
  declares.
- `base32.eyg` is checked against the RFC 4648 vectors.
- The chain is per publisher, not per package. That was read off the live
  ledger: two releases of different packages share one chain and their
  `version` is their position in it.
What is not tested here is the hub accepting a release, which needs a hub. On
eyg.run today `owner` answers `None` even for `standard`, so either ownership
predates the grant table or production runs an older build than this branch.
