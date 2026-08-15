import gleam/int
import gleam/list
import gleam/set
import hashi/game
import hashi/harness
import hashi/state
import shared/hashi

/// Two islands, four cells apart on a single row, joined by one bridge.
///
/// ```txt
/// 1 . . 1
/// ```
fn pair() {
  hashi.from_islands_and_connections(
    width: 4,
    height: 1,
    islands: set.from_list([#(0, 0), #(3, 0)]),
    connections: [#(#(0, 0), #(3, 0), hashi.Single)],
  )
  |> game.new
}

/// A square of four islands, each joined to two neighbours.
///
/// ```txt
/// 2 . 2
/// . . .
/// 2 . 2
/// ```
fn square() {
  hashi.from_islands_and_connections(
    width: 3,
    height: 3,
    islands: set.from_list([#(0, 0), #(2, 0), #(0, 2), #(2, 2)]),
    connections: [
      #(#(0, 0), #(2, 0), hashi.Single),
      #(#(0, 0), #(0, 2), hashi.Single),
      #(#(2, 0), #(2, 2), hashi.Single),
      #(#(0, 2), #(2, 2), hashi.Single),
    ],
  )
  |> game.new
}

/// Four islands whose bridges would have to cross in the middle. This is not a
/// solvable puzzle, it is here so a bridge can get in another one's way.
///
/// ```txt
/// . 1 .
/// 1 . 1
/// . 1 .
/// ```
fn crossroads() {
  hashi.from_islands_and_connections(
    width: 3,
    height: 3,
    islands: set.from_list([#(1, 0), #(1, 2), #(0, 1), #(2, 1)]),
    connections: [
      #(#(1, 0), #(1, 2), hashi.Single),
      #(#(0, 1), #(2, 1), hashi.Single),
    ],
  )
  |> game.new
}

pub fn islands_are_listed_in_reading_order_test() {
  assert game.islands(square())
    == [
      harness.Island(position: #(0, 0), target: 2),
      harness.Island(position: #(2, 0), target: 2),
      harness.Island(position: #(0, 2), target: 2),
      harness.Island(position: #(2, 2), target: 2),
    ]
}

pub fn a_target_counts_both_ends_of_a_double_bridge_test() {
  let game =
    hashi.from_islands_and_connections(
      width: 4,
      height: 1,
      islands: set.from_list([#(0, 0), #(3, 0)]),
      connections: [#(#(0, 0), #(3, 0), hashi.Double)],
    )
    |> game.new
  assert game.islands(game)
    == [
      harness.Island(position: #(0, 0), target: 2),
      harness.Island(position: #(3, 0), target: 2),
    ]
}

pub fn a_new_game_has_no_bridges_test() {
  assert game.bridges(square()) == []
}

pub fn a_bridge_is_listed_once_from_either_end_test() {
  let #(game, result) = game.add_bridge(pair(), #(0, 0), #(3, 0))
  assert result == Ok(Nil)
  assert game.bridges(game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 1)]
}

pub fn a_second_bridge_between_the_same_islands_doubles_it_test() {
  let #(game, _) = game.add_bridge(pair(), #(0, 0), #(3, 0))
  let #(game, result) = game.add_bridge(game, #(0, 0), #(3, 0))
  assert result == Ok(Nil)
  assert game.bridges(game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 2)]
}

pub fn a_third_bridge_is_refused_as_full_test() {
  let #(game, _) = game.add_bridge(pair(), #(0, 0), #(3, 0))
  let #(game, _) = game.add_bridge(game, #(0, 0), #(3, 0))
  let #(game, result) = game.add_bridge(game, #(0, 0), #(3, 0))
  assert result == Error(harness.Full)
  assert game.bridges(game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 2)]
}

pub fn an_empty_cell_is_a_bad_start_test() {
  let #(_, result) = game.add_bridge(pair(), #(1, 0), #(3, 0))
  assert result == Error(harness.BadStart)
}

pub fn an_empty_cell_is_a_bad_end_test() {
  let #(_, result) = game.add_bridge(pair(), #(0, 0), #(2, 0))
  assert result == Error(harness.BadEnd)
}

pub fn an_island_cannot_bridge_to_itself_test() {
  let #(_, result) = game.add_bridge(pair(), #(0, 0), #(0, 0))
  assert result == Error(harness.BadEnd)
}

pub fn islands_out_of_line_cannot_be_joined_test() {
  let #(_, result) = game.add_bridge(square(), #(0, 0), #(2, 2))
  assert result == Error(harness.BadEnd)
}

pub fn a_bridge_cannot_cross_another_test() {
  let #(game, result) = game.add_bridge(crossroads(), #(1, 0), #(1, 2))
  assert result == Ok(Nil)
  let #(_, result) = game.add_bridge(game, #(0, 1), #(2, 1))
  assert result == Error(harness.BadEnd)
}

pub fn a_matching_solution_completes_the_game_test() {
  let game = square()
  assert !game.is_complete(game)
  let #(game, _) = game.add_bridge(game, #(0, 0), #(2, 0))
  let #(game, _) = game.add_bridge(game, #(0, 0), #(0, 2))
  let #(game, _) = game.add_bridge(game, #(2, 0), #(2, 2))
  assert !game.is_complete(game)
  let #(game, _) = game.add_bridge(game, #(0, 2), #(2, 2))
  assert game.is_complete(game)
}

pub fn undo_takes_back_the_last_bridge_test() {
  let #(game, _) = game.add_bridge(pair(), #(0, 0), #(3, 0))
  let #(game, moved) = game.undo(game)
  assert moved
  assert game.bridges(game) == []
}

pub fn there_is_nothing_to_undo_in_a_new_game_test() {
  let #(game, moved) = game.undo(pair())
  assert !moved
  assert game.bridges(game) == []
}

pub fn redo_puts_the_bridge_back_test() {
  let #(game, _) = game.add_bridge(pair(), #(0, 0), #(3, 0))
  let #(game, _) = game.undo(game)
  let #(game, moved) = game.redo(game)
  assert moved
  assert game.bridges(game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 1)]
}

pub fn there_is_nothing_to_redo_until_something_is_undone_test() {
  let #(game, moved) = game.redo(pair())
  assert !moved
  assert game.bridges(game) == []
}

pub fn a_new_bridge_after_an_undo_drops_the_redo_test() {
  let game = square()
  let #(game, _) = game.add_bridge(game, #(0, 0), #(2, 0))
  let #(game, _) = game.undo(game)
  let #(game, _) = game.add_bridge(game, #(0, 0), #(0, 2))
  let #(game, moved) = game.redo(game)
  assert !moved
  assert game.bridges(game)
    == [harness.Bridge(start: #(0, 0), end: #(0, 2), count: 1)]
}

pub fn the_answer_is_the_bridges_the_puzzle_was_built_from_test() {
  assert game.solution(square())
    == [
      harness.Bridge(start: #(0, 0), end: #(2, 0), count: 1),
      harness.Bridge(start: #(0, 0), end: #(0, 2), count: 1),
      harness.Bridge(start: #(2, 0), end: #(2, 2), count: 1),
      harness.Bridge(start: #(0, 2), end: #(2, 2), count: 1),
    ]
}

/// A generated board can be finished through the same `AddBridge` a program
/// performs, which is the only claim that matters: the harness is enough to
/// play the game with.
pub fn a_generated_board_can_be_solved_through_the_effects_test() {
  use day <- list.each([19_950, 19_951, 19_952, 19_953, 19_954])
  let board = game.new(state.daily(day))
  assert !game.is_complete(board)

  let solved =
    list.fold(game.solution(board), board, fn(board, bridge) {
      let harness.Bridge(start:, end:, count:) = bridge
      // A double bridge is the same move made twice.
      use board, _ <- int.range(from: 0, to: count, with: board)
      let #(board, outcome) = game.add_bridge(board, start, end)
      assert Ok(Nil) == outcome
      board
    })

  assert game.solution(board) == game.bridges(solved)
  assert game.is_complete(solved)
}
