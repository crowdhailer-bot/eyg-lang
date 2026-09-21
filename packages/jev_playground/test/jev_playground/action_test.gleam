import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import jev_playground/action as a
import morph/buffer
import morph/editable as e
import morph/projection as p
import multiformats/cid/v1

pub fn every_action_round_trips_through_json_test() {
  let assert Ok(#(module, _)) =
    v1.from_string(
      "baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja",
    )
  let actions = [
    a.Next,
    a.Previous,
    a.Up,
    a.Down,
    a.Parent,
    a.NextVacant,
    a.JumpToError(2),
    a.Variable("x"),
    a.String(""),
    a.Integer(-3),
    a.Builtin("int_add"),
    a.Tag("Ok"),
    a.Reference(ir.Pinned(ir.Release("standard", 1, module))),
    a.Reference(ir.Content(module)),
    a.OpenLibrary("http"),
    a.EmptyList,
    a.List,
    a.EmptyRecord,
    a.Record(["a", "b"]),
    a.Function("n"),
    a.Call,
    a.CallTaking(3),
    a.CallWith,
    a.Assign("x"),
    a.AssignBefore("y"),
    a.Select("f"),
    a.Overwrite("g"),
    a.Match(["True", "False"]),
    a.Perform("Log"),
    a.Handle("Log"),
    a.InsertBefore(None),
    a.InsertAfter(Some("key")),
    a.Spread,
    a.Delete,
    a.Undo,
    a.Rename("z"),
    a.ChooseString,
    a.ChooseInteger,
    a.Destructure([#("a", "b")]),
    a.RunTests,
    a.Finish,
    a.Compound("variable x, select .f", [a.Variable("x"), a.Select("f")]),
    a.AtHole([1, 0], 2, a.Integer(1)),
  ]
  list.each(actions, fn(action) {
    let encoded = json.to_string(a.to_json(action))
    assert json.parse(encoded, a.decoder()) == Ok(action)
  })
}

pub fn calls_take_at_most_eight_arguments_test() {
  let params =
    int.range(1, 11, [], fn(acc, i) { [e.Bind("p" <> int.to_string(i)), ..acc] })
  let source =
    e.Block(
      [#(e.Bind("f"), e.Function(params, e.Integer(1)))],
      e.Variable("f"),
      True,
    )
  let buffer =
    buffer.from_projection(p.focus_at(source, [1]), infer.pure(), dict.new())
  assert buffer.target_arity(buffer) == Ok(10)
  assert a.call_arity(buffer) == 8
}
