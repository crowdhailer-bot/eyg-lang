//// The puzzle, and the six things a program is allowed to do to it.
////
//// Every line of rendering and rules here comes from the original hashi
//// project: `shared/hashi` generates and checks puzzles, `frontend/hashi_grid`
//// holds the board a player is working on and draws it. This module only turns
//// that into the shape the harness describes, so nothing about how the game
//// works is written twice.
////
//// The board is drawn but it is not played with. `view` throws away every
//// message the grid produces, so a pointer on the board does nothing at all:
//// the only way to move is to run a program.

import frontend/hashi_grid
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{type Order}
import gleam/result
import hashi/harness.{type Position}
import lustre/element.{type Element}
import shared/hashi.{type Puzzle}

pub opaque type Game {
  Game(puzzle: Puzzle, grid: hashi_grid.Model)
}

pub fn new(puzzle: Puzzle) -> Game {
  let grid =
    hashi_grid.init(hashi_grid.InitState(puzzle:, connections: dict.new()))
  Game(puzzle:, grid:)
}

/// Every island on the board, in reading order, with the number of bridge ends
/// it needs to finish the game with.
pub fn islands(game: Game) -> List(harness.Island) {
  let Game(puzzle:, ..) = game
  let width = hashi.width(puzzle)
  let height = hashi.height(puzzle)

  {
    use found, y <- int.range(from: 0, to: height, with: [])
    use found, x <- int.range(from: 0, to: width, with: found)
    case hashi.has_island(puzzle, #(x, y)) {
      False -> found
      True -> {
        let target = hashi.island_rank(puzzle, #(x, y)) |> result.unwrap(0)
        [harness.Island(position: #(x, y), target:), ..found]
      }
    }
  }
  |> list.reverse
}

/// The bridges built so far, in reading order of their starting island. The
/// grid keeps a connection from either end; each bridge is reported once, from
/// whichever of its two islands comes first.
pub fn bridges(game: Game) -> List(harness.Bridge) {
  let Game(grid:, ..) = game
  let hashi_grid.Solution(connections:, ..) = hashi_grid.current_solution(grid)
  listed(connections)
}

/// The bridges the puzzle was built from: the answer.
///
/// The game never shows this to a player. It is here so a demonstration can be
/// scripted, and so a test can solve a generated board through the same effects
/// a program would.
///
/// The original project keeps a puzzle's own connections to itself, but writes
/// them out when it serialises one, and hands back a decoder for them. So this
/// asks the puzzle to describe itself and reads the answer out of that, rather
/// than reaching inside it.
pub fn solution(game: Game) -> List(harness.Bridge) {
  let Game(puzzle:, ..) = game
  let assert Ok(connections) =
    json.parse(
      json.to_string(hashi.to_json(puzzle)),
      decode.field("connections", hashi.connections_decoder(), decode.success),
    )
  listed(connections)
}

/// The grid keeps a connection from either end; each bridge is reported once,
/// from whichever of its two islands comes first, in reading order.
fn listed(connections) -> List(harness.Bridge) {
  {
    use #(start, connections) <- list.flat_map(dict.to_list(connections))
    use #(end, bridge) <- list.filter_map(dict.to_list(connections))
    case reading_order(start, end) {
      order.Lt -> {
        let count = case bridge {
          hashi.Single -> 1
          hashi.Double -> 2
        }
        Ok(harness.Bridge(start:, end:, count:))
      }
      _ -> Error(Nil)
    }
  }
  |> list.sort(fn(one, other) {
    case reading_order(one.start, other.start) {
      order.Eq -> reading_order(one.end, other.end)
      first -> first
    }
  })
}

/// Build a bridge, or say why it cannot be built.
pub fn add_bridge(
  game: Game,
  start: Position,
  end: Position,
) -> #(Game, Result(Nil, harness.BridgeError)) {
  case hashi_grid.add_bridge(game.grid, start, end) {
    Ok(grid) -> #(Game(..game, grid:), Ok(Nil))
    Error(reason) -> #(game, Error(translate(reason)))
  }
}

fn translate(reason: hashi_grid.BridgeError) -> harness.BridgeError {
  case reason {
    hashi_grid.BadStart -> harness.BadStart
    hashi_grid.BadEnd -> harness.BadEnd
    hashi_grid.Full -> harness.Full
  }
}

/// Step back through the moves made so far, answering whether there was a move
/// to take back.
pub fn undo(game: Game) -> #(Game, Bool) {
  case hashi_grid.can_step_back(game.grid) {
    False -> #(game, False)
    True -> #(Game(..game, grid: hashi_grid.step_back(game.grid)), True)
  }
}

/// Step forward through moves that were taken back, answering whether there
/// was a move to put back.
pub fn redo(game: Game) -> #(Game, Bool) {
  case hashi_grid.can_step_forward(game.grid) {
    False -> #(game, False)
    True -> #(Game(..game, grid: hashi_grid.step_forward(game.grid)), True)
  }
}

/// Whether every island has the bridges it asked for and the whole board is
/// joined into one group.
pub fn is_complete(game: Game) -> Bool {
  hashi_grid.is_complete(game.grid)
}

pub fn width(game: Game) -> Int {
  hashi.width(game.puzzle)
}

pub fn height(game: Game) -> Int {
  hashi.height(game.puzzle)
}

/// The board, drawn by the original project. Every pointer message the grid
/// produces becomes `ignore`: the board is something to look at, not something
/// to click.
pub fn view(game: Game, ignore: msg) -> Element(msg) {
  element.map(hashi_grid.view(game.grid), fn(_) { ignore })
}

fn reading_order(one: Position, other: Position) -> Order {
  let #(x, y) = one
  let #(other_x, other_y) = other
  case int.compare(y, other_y) {
    order.Eq -> int.compare(x, other_x)
    first -> first
  }
}
