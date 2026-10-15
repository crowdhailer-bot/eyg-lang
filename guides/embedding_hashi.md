---
name: Playing Hashi through EYG
description: Give a puzzle shell and an agent only the original game's operations.
---

# Playing Hashi through EYG

[examples/hashi](../examples/hashi/) adapts the public game API of
[Giacomo Cavalieri's Hashi](https://github.com/giacomocavalieri/hashi), pinned
to commit 6ad02b9ad90490a9cf05ade95beb97814f19c511. The upstream project supplies
puzzle generation, the board view, move rules, history and completion checks.
The adapter builds a bridge by sending the same pair of island presses as a
person. Refused moves discard the intermediate selection.

The typed interface offers ListIslands, ListBridges, AddBridge, RemoveBridge,
Undo, Redo, IsSolved and Print. Moves take `{from: {x, y}, to: {x, y}}` and
return Ok({}) or Error with NoIsland, NotReachable, Full, NoBridge or
AlreadySolved. Coordinates start at zero in the top left. Upstream rules
reject crossing bridges and more than two bridges between a pair of islands.

From examples/hashi, run `gleam test` and `gleam test --runtime node`.
The board tests exercise actual upstream transitions, crossing and invalid
endpoints, double bridges, removal, undo/redo and solved-board refusal.

## Retained shell and solver

`hashi/play.start(library)` creates a shell with the game effects and the
[library](../examples/hashi/library.eyg) in scope as `hashi`. Keep the returned
shell and board after each `play.run`; variables persist between runs.
The library has no package references, so these programs make no hub requests.
Keeping the shell retains its checked functions and values; recreating it
rechecks them. The host owns this lifetime, as in the
[BEAM embedding examples](./embedding_erlang.md#package-ownership).

```eyg
let islands = hashi.unfinished({})
hashi.map(islands, (island) -> { {x: island.x, y: island.y, missing: hashi.missing(island)} })
```

The helpers query islands and neighbours, count existing bridges and connect
or disconnect pairs. Game refusals are ordinary tagged results. Type errors,
including unavailable effects, stop the whole program before any move.

Run [solver.eyg](../examples/hashi/solver.eyg) in the shell to retain `solve`,
then run `solve({})`. It repeatedly adds bridges forced by the numbers and
stops when no more are forced, returning IsSolved. It does not guess or search:
the tests solve seed 1 and verify a partial, unsolved result on seed 2.
