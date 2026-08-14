//// The context is a library over the six effects, so it is tested the way a
//// person would use it: run a program against a real board and look at what
//// comes back.

import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import hashi/context
import hashi/game
import hashi/platform
import hashi/source
import ogre/origin
import overlay/web/tools
import shared/hashi

/// A square of four islands, each wanting two bridge ends.
///
/// ```txt
/// 2.2
/// ...
/// 2.2
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
}

fn loaded() {
  let assert Ok(context) = context.load(source.read("eyg/context.eyg"))
  context
}

fn workspace(puzzle) {
  let context.Context(readme:, scope:, ..) = loaded()
  let host =
    platform.Host(game: game.new(puzzle), origin: origin.https("hashi.test"))
  tools.Context(
    environment: platform.environment(host, readme, scope),
    cache: cache.ready(),
    counter: 0,
    effects: [],
  )
}

/// Run a program and answer with the workspace it left behind and the value.
fn run(ctx, code) {
  let assert Ok(tree) = parser.all_from_string(code)
  let #(ctx, call) = tools.run(ctx, ir.map_annotation(tree, fn(_) { [] }))
  #(ctx, call)
}

fn answer(ctx, code) {
  let #(ctx, call) = run(ctx, code)
  let assert tools.Successful(value) = call
  #(ctx, value)
}

fn printed(ctx, code) {
  let #(ctx, value) = answer(ctx, code)
  let assert v.String(drawn) = value
  #(ctx, drawn)
}

pub fn the_context_says_what_it_is_for_test() {
  let context.Context(readme:, scope:, ..) = loaded()
  assert string.starts_with(readme, "# Hashiwokakero")
  // the readme is honest about there being no network here
  assert string.contains(readme, "no network here")
  let names = list.map(scope, fn(pair) { pair.0 })
  assert list.contains(names, "picture")
  assert list.contains(names, "connect")
  assert list.contains(names, "twos")
}

pub fn the_board_draws_itself_test() {
  let #(_, drawn) = printed(workspace(square()), "picture({})")
  assert "2.2\n...\n2.2\n" == drawn
}

pub fn a_bridge_shows_up_in_the_picture_test() {
  let ctx = workspace(square())
  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(ctx, drawn) = printed(ctx, "picture({})")
  assert "2-2\n...\n2.2\n" == drawn

  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 0, y: 2})")
  let #(_, drawn) = printed(ctx, "picture({})")
  assert "2-2\n|..\n2.2\n" == drawn
}

pub fn a_double_bridge_is_drawn_differently_test() {
  let ctx = workspace(square())
  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(_, drawn) = printed(ctx, "picture({})")
  assert "2=2\n...\n2.2\n" == drawn
}

pub fn twos_finds_the_islands_wanting_two_test() {
  let #(_, value) = answer(workspace(square()), "count(twos({}))")
  assert v.Integer(4) == value
}

pub fn neighbours_are_the_islands_in_line_test() {
  let ctx = workspace(square())
  let #(ctx, value) =
    answer(
      ctx,
      "match neighbours({x: 0, y: 0}).right {
  Ok(island) -> { island.position }
  Error(_) -> { {x: -1, y: -1} }
}",
    )
  assert position(2, 0) == value

  let #(ctx, value) =
    answer(
      ctx,
      "match neighbours({x: 0, y: 0}).down {
  Ok(island) -> { island.position }
  Error(_) -> { {x: -1, y: -1} }
}",
    )
  assert position(0, 2) == value

  // nothing is up or left of the top left corner
  let #(_, value) =
    answer(
      ctx,
      "match neighbours({x: 0, y: 0}).up {
  Ok(_) -> { True({}) }
  Error(_) -> { False({}) }
}",
    )
  assert v.false() == value
}

pub fn around_drops_the_directions_test() {
  let #(_, value) = answer(workspace(square()), "count(around({x: 0, y: 0}))")
  assert v.Integer(2) == value
}

pub fn ends_and_remaining_follow_the_bridges_test() {
  let ctx = workspace(square())
  let #(ctx, value) = answer(ctx, "ends({x: 0, y: 0})")
  assert v.Integer(0) == value

  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(ctx, value) = answer(ctx, "ends({x: 0, y: 0})")
  assert v.Integer(1) == value
  let #(ctx, value) = answer(ctx, "remaining({x: 0, y: 0})")
  assert v.ok(v.Integer(1)) == value

  let #(_, value) = answer(ctx, "remaining({x: 1, y: 1})")
  assert v.error(v.unit()) == value
}

pub fn a_refused_bridge_says_why_test() {
  let ctx = workspace(square())
  let refusal =
    "match connect(start, end) {
  Ok(_) -> { \"built\" }
  Error(reason) -> {
    match reason {
      BadStart(_) -> { \"bad start\" }
      BadEnd(_) -> { \"bad end\" }
      Full(_) -> { \"full\" }
    }
  }
}"

  let #(ctx, said) =
    printed(
      ctx,
      "let start = {x: 1, y: 1}\nlet end = {x: 2, y: 0}\n" <> refusal,
    )
  assert "bad start" == said

  let #(ctx, said) =
    printed(
      ctx,
      "let start = {x: 0, y: 0}\nlet end = {x: 2, y: 2}\n" <> refusal,
    )
  assert "bad end" == said

  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(_, said) =
    printed(
      ctx,
      "let start = {x: 0, y: 0}\nlet end = {x: 2, y: 0}\n" <> refusal,
    )
  assert "full" == said
}

pub fn a_crossing_bridge_is_refused_test() {
  // Four islands whose bridges would have to cross in the middle.
  let puzzle =
    hashi.from_islands_and_connections(
      width: 3,
      height: 3,
      islands: set.from_list([#(1, 0), #(1, 2), #(0, 1), #(2, 1)]),
      connections: [
        #(#(1, 0), #(1, 2), hashi.Single),
        #(#(0, 1), #(2, 1), hashi.Single),
      ],
    )
  let ctx = workspace(puzzle)
  let #(ctx, value) = answer(ctx, "connect({x: 1, y: 0}, {x: 1, y: 2})")
  assert v.ok(v.unit()) == value
  let #(_, value) = answer(ctx, "connect({x: 0, y: 1}, {x: 2, y: 1})")
  assert v.error(v.Tagged("BadEnd", v.unit())) == value
}

pub fn solving_the_board_empties_unfinished_test() {
  let ctx = workspace(square())
  let #(ctx, value) = answer(ctx, "count(unfinished({}))")
  assert v.Integer(4) == value

  let #(ctx, value) =
    answer(
      ctx,
      "let _ = connect({x: 0, y: 0}, {x: 2, y: 0})
let _ = connect({x: 0, y: 0}, {x: 0, y: 2})
let _ = connect({x: 2, y: 0}, {x: 2, y: 2})
let _ = connect({x: 0, y: 2}, {x: 2, y: 2})
is_empty(unfinished({}))",
    )
  assert v.true() == value

  let tools.Context(environment: solved, ..) = ctx
  let platform.Host(game: board, ..) = solved.host
  assert game.is_complete(board)
}

pub fn undo_and_redo_reach_the_history_test() {
  let ctx = workspace(square())
  let #(ctx, _) = answer(ctx, "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let #(ctx, value) = answer(ctx, "undo({})")
  assert v.true() == value
  let #(ctx, drawn) = printed(ctx, "picture({})")
  assert "2.2\n...\n2.2\n" == drawn

  let #(ctx, value) = answer(ctx, "redo({})")
  assert v.true() == value
  let #(ctx, drawn) = printed(ctx, "picture({})")
  assert "2-2\n...\n2.2\n" == drawn

  let #(_, value) = answer(ctx, "redo({})")
  assert v.false() == value
}

pub fn a_program_cannot_reach_outside_the_game_test() {
  let #(_, call) = run(workspace(square()), "perform Fetch({})")
  let assert tools.Exception(reason) = call
  assert string.contains(simple_debug.describe(reason), "Fetch")
}

fn position(x, y) {
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}
