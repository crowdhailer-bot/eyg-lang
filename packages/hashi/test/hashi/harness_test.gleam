import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import hashi/harness
import touch_grass/interface.{Interface}

fn position(x, y) {
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}

pub fn every_game_effect_is_in_the_harness_test() {
  let names = list.map(harness.effects(), fn(i) { i.name })
  assert names
    == [
      "ListIslands",
      "ListBridges",
      "AddBridge",
      "ShareOutcome",
      "Undo",
      "Redo",
    ]
}

pub fn the_harness_has_no_browser_effects_test() {
  let names = list.map(harness.effects(), fn(i) { i.name })
  assert !list.contains(names, "Fetch")
  assert !list.contains(names, "Alert")
  assert !list.contains(names, "Print")
}

pub fn list_islands_casts_from_unit_test() {
  assert harness.cast("ListIslands", v.unit()) == Ok(harness.ListIslands)
}

pub fn list_bridges_casts_from_unit_test() {
  assert harness.cast("ListBridges", v.unit()) == Ok(harness.ListBridges)
}

pub fn undo_and_redo_cast_from_unit_test() {
  assert harness.cast("Undo", v.unit()) == Ok(harness.Undo)
  assert harness.cast("Redo", v.unit()) == Ok(harness.Redo)
}

pub fn add_bridge_casts_a_start_and_end_test() {
  let lift =
    v.Record(
      dict.from_list([#("start", position(0, 1)), #("end", position(3, 1))]),
    )
  assert harness.cast("AddBridge", lift)
    == Ok(harness.AddBridge(start: #(0, 1), end: #(3, 1)))
}

pub fn add_bridge_needs_both_ends_test() {
  let lift = v.Record(dict.from_list([#("start", position(0, 1))]))
  assert harness.cast("AddBridge", lift) == Error(break.MissingField("end"))
}

pub fn add_bridge_needs_integer_coordinates_test() {
  let start =
    v.Record(dict.from_list([#("x", v.String("0")), #("y", v.Integer(1))]))
  let lift =
    v.Record(dict.from_list([#("start", start), #("end", position(3, 1))]))
  assert harness.cast("AddBridge", lift)
    == Error(break.IncorrectTerm("Integer", v.String("0")))
}

pub fn share_outcome_casts_the_message_test() {
  assert harness.cast("ShareOutcome", v.String("solved in 12 moves"))
    == Ok(harness.ShareOutcome("solved in 12 moves"))
}

pub fn an_unknown_effect_is_unhandled_test() {
  assert harness.cast("Fetch", v.unit())
    == Error(break.UnhandledEffect("Fetch", v.unit()))
}

pub fn islands_encode_position_and_target_test() {
  let islands = [
    harness.Island(position: #(0, 0), target: 2),
    harness.Island(position: #(3, 0), target: 1),
  ]
  assert harness.islands_encode(islands)
    == v.LinkedList([
      v.Record(
        dict.from_list([
          #("position", position(0, 0)),
          #("target", v.Integer(2)),
        ]),
      ),
      v.Record(
        dict.from_list([
          #("position", position(3, 0)),
          #("target", v.Integer(1)),
        ]),
      ),
    ])
}

pub fn bridges_encode_both_ends_and_a_count_test() {
  let bridges = [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 2)]
  assert harness.bridges_encode(bridges)
    == v.LinkedList([
      v.Record(
        dict.from_list([
          #("start", position(0, 0)),
          #("end", position(3, 0)),
          #("count", v.Integer(2)),
        ]),
      ),
    ])
}

pub fn a_placed_bridge_encodes_as_ok_test() {
  assert harness.add_bridge_encode(Ok(Nil)) == v.ok(v.unit())
}

pub fn a_refused_bridge_encodes_the_reason_test() {
  assert harness.add_bridge_encode(Error(harness.BadStart))
    == v.error(v.Tagged("BadStart", v.unit()))
  assert harness.add_bridge_encode(Error(harness.BadEnd))
    == v.error(v.Tagged("BadEnd", v.unit()))
  assert harness.add_bridge_encode(Error(harness.Full))
    == v.error(v.Tagged("Full", v.unit()))
}

pub fn undo_encodes_whether_it_moved_test() {
  assert harness.step_encode(True) == v.true()
  assert harness.step_encode(False) == v.false()
}

pub fn sharing_encodes_a_result_test() {
  assert harness.share_outcome_encode(Ok(Nil)) == v.ok(v.unit())
  assert harness.share_outcome_encode(Error("no account connected"))
    == v.error(v.String("no account connected"))
}

pub fn the_types_are_named_for_inference_test() {
  let types = harness.types(harness.effects())
  let names = list.map(types, fn(pair) { pair.0 })
  assert names
    == [
      "ListIslands",
      "ListBridges",
      "AddBridge",
      "ShareOutcome",
      "Undo",
      "Redo",
    ]
}

pub fn take_selects_a_subset_of_the_harness_test() {
  let taken = harness.take(["ListIslands", "Undo"])
  assert list.map(taken, fn(i) {
      let Interface(name:, ..) = i
      name
    })
    == ["ListIslands", "Undo"]
}
