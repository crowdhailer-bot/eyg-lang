import eyg/interpreter/value as v
import eyg/parser
import gleam/int
import jev_playground/environment
import jev_playground/run
import morph/editable as e

pub fn a_program_that_never_finishes_is_stopped_test() {
  let assert Ok(tree) =
    parser.all_from_string("let f = !fix((self, x) -> { self(x) })\nf(0)")
  let source = e.to_annotated(e.from_annotated(tree), [])
  assert run.evaluate(source, environment.pure())
    == Error("the program did not finish within a million steps")
}

pub fn effects_are_handled_with_state_and_scope_values_test() {
  let assert Ok(tree) =
    parser.all_from_string(
      "let a = perform Ask(name)\nlet b = perform Ask(name)\n!string_append(a, b)",
    )
  let source = e.to_annotated(e.from_annotated(tree), [])
  let environment =
    environment.Environment(..environment.pure(), values: [
      #("name", v.String("Ada")),
    ])
  let handle = fn(count, label, lift) {
    case label, lift {
      "Ask", v.String(name) ->
        Ok(#(v.String(name <> int.to_string(count)), count + 1))
      _, _ -> Error("unexpected " <> label)
    }
  }
  assert run.evaluate_handled(source, environment, 1, handle)
    == Ok(#(v.String("Ada1Ada2"), 3))
}
