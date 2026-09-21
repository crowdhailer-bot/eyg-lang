import eyg/parser
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
