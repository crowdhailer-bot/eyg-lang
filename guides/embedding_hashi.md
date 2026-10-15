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
