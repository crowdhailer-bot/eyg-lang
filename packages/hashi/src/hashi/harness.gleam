//// The harness describes every effect available to EYG code running in the
//// game. It is the whole of the interface between a program and the puzzle:
//// there is nothing else an EYG program can reach from here.
////
//// This is modelled on `touch_grass/harness/browser`, but where that harness
//// describes a browser this one describes a single application. There is no
//// `Fetch`, no `Print` and no clipboard. A program can read the board, build a
//// bridge, step through the history and share a finished game, and that is all.
//// Sharing needs the network, so the platform makes that request; the program
//// never gets to choose the host it talks to.
////
//// Positions are `{x, y}` records with the origin at the top left, the same
//// coordinate space the original hashi project uses.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result.{try}
import multiformats/cid/v1
import touch_grass/interface.{type Interface, Interface}

/// A cell on the board.
pub type Position =
  #(Int, Int)

/// An island, and the number of bridge ends it must finish the game with.
pub type Island {
  Island(position: Position, target: Int)
}

/// Bridges between two islands. `count` is 1 or 2, the game allows no more.
pub type Bridge {
  Bridge(start: Position, end: Position, count: Int)
}

/// Why a bridge could not be built.
pub type BridgeError {
  /// There is no island at the start position.
  BadStart
  /// There is no island at the end position, or nothing can reach it from the
  /// start: it is not in line, or another island or bridge is in the way.
  BadEnd
  /// The two islands are already joined by a double bridge.
  Full
}

/// Every effect an EYG program can perform inside the game.
pub type Effect {
  ListIslands
  ListBridges
  AddBridge(start: Position, end: Position)
  ShareOutcome(text: String)
  Undo
  Redo
}

/// The harness types concretely implementing the game harness effect types.
pub type Harness(a, b) =
  List(Interface(Effect, a, b))

// TYPES -----------------------------------------------------------------------

pub fn position() {
  t.record([#("x", t.Integer), #("y", t.Integer)])
}

pub fn island() {
  t.record([#("position", position()), #("target", t.Integer)])
}

pub fn bridge() {
  t.record([
    #("start", position()),
    #("end", position()),
    #("count", t.Integer),
  ])
}

pub fn span() {
  t.record([#("start", position()), #("end", position())])
}

pub fn bridge_error() {
  t.union([#("BadStart", t.unit), #("BadEnd", t.unit), #("Full", t.unit)])
}

// CASTING ---------------------------------------------------------------------

pub fn position_decode(value) {
  use x <- try(cast.field("x", cast.as_integer, value))
  use y <- try(cast.field("y", cast.as_integer, value))
  Ok(#(x, y))
}

fn span_decode(value) {
  use start <- try(cast.field("start", position_decode, value))
  use end <- try(cast.field("end", position_decode, value))
  Ok(AddBridge(start:, end:))
}

// ENCODING --------------------------------------------------------------------

pub fn position_encode(position: Position) {
  let #(x, y) = position
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}

pub fn islands_encode(islands: List(Island)) {
  v.LinkedList(
    list.map(islands, fn(island) {
      let Island(position:, target:) = island
      v.Record(
        dict.from_list([
          #("position", position_encode(position)),
          #("target", v.Integer(target)),
        ]),
      )
    }),
  )
}

pub fn bridges_encode(bridges: List(Bridge)) {
  v.LinkedList(
    list.map(bridges, fn(bridge) {
      let Bridge(start:, end:, count:) = bridge
      v.Record(
        dict.from_list([
          #("start", position_encode(start)),
          #("end", position_encode(end)),
          #("count", v.Integer(count)),
        ]),
      )
    }),
  )
}

pub fn bridge_error_encode(reason: BridgeError) {
  case reason {
    BadStart -> v.Tagged("BadStart", v.unit())
    BadEnd -> v.Tagged("BadEnd", v.unit())
    Full -> v.Tagged("Full", v.unit())
  }
}

pub fn add_bridge_encode(result: Result(Nil, BridgeError)) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(bridge_error_encode(reason))
  }
}

/// `Undo` and `Redo` answer whether there was a step to take.
pub fn step_encode(moved: Bool) {
  v.bool(moved)
}

pub fn share_outcome_encode(result: Result(Nil, String)) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}

// THE HARNESS -----------------------------------------------------------------

pub fn effects() -> Harness(a, b) {
  [
    Interface(
      name: "ListIslands",
      lift_type: t.unit,
      lower_type: t.List(island()),
      decode: cast.as_unit(_, ListIslands),
    ),
    Interface(
      name: "ListBridges",
      lift_type: t.unit,
      lower_type: t.List(bridge()),
      decode: cast.as_unit(_, ListBridges),
    ),
    Interface(
      name: "AddBridge",
      lift_type: span(),
      lower_type: t.result(t.unit, bridge_error()),
      decode: span_decode,
    ),
    Interface(
      name: "ShareOutcome",
      lift_type: t.String,
      lower_type: t.result(t.unit, t.String),
      decode: cast.map(cast.as_string, ShareOutcome),
    ),
    Interface(
      name: "Undo",
      lift_type: t.unit,
      lower_type: t.boolean,
      decode: cast.as_unit(_, Undo),
    ),
    Interface(
      name: "Redo",
      lift_type: t.unit,
      lower_type: t.boolean,
      decode: cast.as_unit(_, Redo),
    ),
  ]
}

pub fn take(labels) -> Harness(a, b) {
  list.filter(effects(), fn(interface) {
    let Interface(name:, ..) = interface
    list.any(labels, fn(l) { l == name })
  })
}

pub fn cast(
  label: String,
  input: v.Value(a, b),
) -> Result(Effect, break.Reason(a, b)) {
  case list.find(effects(), fn(i) { i.name == label }) {
    Ok(Interface(decode:, ..)) -> decode(input)
    Error(Nil) -> Error(break.UnhandledEffect(label, input))
  }
}

pub fn types(
  harness: Harness(_, _),
) -> List(#(String, #(t.Type(Int), t.Type(Int)))) {
  list.map(harness, fn(interface) {
    let Interface(name:, lift_type:, lower_type:, ..) = interface
    #(name, #(lift_type, lower_type))
  })
}

pub fn infer_context(
  references: dict.Dict(v1.Cid, t.Type(#(Bool, Int))),
) -> infer.Context {
  infer.pure()
  |> infer.with_references(references)
  |> infer.with_effects(types(effects()))
}

pub fn decode_list(harness: Harness(_, _)) {
  list.map(harness, fn(interface) {
    let Interface(name:, decode:, ..) = interface
    #(name, decode)
  })
}
