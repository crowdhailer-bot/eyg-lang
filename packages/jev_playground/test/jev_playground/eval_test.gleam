import eyg/parser
import gleam/list
import jev_playground/environment
import jev_playground/eval as evals
import jev_playground/library
import jev_playground/packages
import morph/editable as e

fn environment() {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, environment.pure())
  environment
}

fn annotated(source) {
  let assert Ok(tree) = parser.all_from_string(source)
  e.to_annotated(e.from_annotated(tree), [])
}

pub fn every_solution_passes_its_check_test() {
  let environment = environment()
  list.each(evals.all(), fn(eval) {
    let source = annotated(evals.solution(eval))
    assert evals.check(eval, source, environment) == Ok(Nil)
  })
}

pub fn list_functions_start_fails_its_check_test() {
  let eval = evals.list_functions()
  let assert Error(reason) =
    evals.check(eval, annotated(eval.start), environment())
  assert reason == "the record has no `sum`"
}

pub fn every_start_fails_its_check_test() {
  let environment = environment()
  list.each(evals.all(), fn(eval) {
    let assert Ok(start) = evals.start(eval)
    let assert Error(_) =
      evals.check(eval, e.to_annotated(start, []), environment)
  })
}
