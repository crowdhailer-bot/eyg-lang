import eyg/analysis/inference/levels_j/contextual as infer
import gleam/dict
import gleam/list
import gleam/option.{None}
import morph/buffer
import morph/editable as e
import morph/projection as p

fn at(source, path) {
  buffer.from_projection(p.focus_at(source, path), infer.pure(), dict.new())
}

// Paths are chosen to not read the same reversed, as annotations use reversed paths.
pub fn scope_is_found_at_the_focus_test() {
  let source =
    e.Function(
      [e.Bind("x"), e.Bind("w")],
      e.Block([#(e.Bind("y"), e.Vacant)], e.Variable("y"), True),
    )
  let assert Ok(scope) = buffer.target_scope(at(source, [2, 0, 1]))
  assert list.map(scope, fn(entry) { entry.0 }) == ["w", "x"]
}

pub fn arity_is_found_at_the_focus_test() {
  let source =
    e.Block(
      [#(e.Bind("f"), e.Builtin("int_add")), #(e.Bind("g"), e.Integer(1))],
      e.Call(e.Variable("f"), [e.Vacant]),
      True,
    )
  assert buffer.target_arity(at(source, [2, 0])) == Ok(2)
  assert buffer.target_arity(at(e.Record([], None), [])) == Error(Nil)
}

pub fn focusing_on_a_path_that_does_not_exist_fails_test() {
  let source = e.Call(e.Variable("f"), [e.Integer(1)])
  let buffer = at(source, [])
  let assert Ok(focused) = buffer.focus_at(buffer, [1])
  assert focused.projection.0 == p.Exp(e.Integer(1))
  assert buffer.focus_at(buffer, [1, 0]) == Error(Nil)
}
