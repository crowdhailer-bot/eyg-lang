import gleam/int
import gleam/javascript/promise
import gleam/option.{None}
import loam/sandbox
import loam/system
import simplifile

pub fn resolve_relative_paths_test() {
  assert system.resolve_relative("/project/src", "../data/./file")
    == Ok("/project/data/file")
  assert system.resolve_relative("/project/src", "/other/file")
    == Ok("/other/file")
  assert system.resolve_relative("src", "../data/file") == Ok("data/file")
  // assert system.resolve_relative("/project", "data/") == Ok("/project/data/")
  assert system.resolve_relative("/project", "../") == Ok("/")
  assert system.resolve_relative("src", "../") == Ok("")
}

pub fn unresolvable_paths_are_invalid_arguments_test() {
  assert system.resolve_relative("/project", "../../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("/project", "/../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("src", "../../file")
    == Error(simplifile.Einval)
}

pub fn traverse_preserves_effect_and_result_order_test() {
  let workflow = {
    use value <- system.traverse([1, 2, 3])
    use Nil <- system.map(system.stdout(int.to_string(value)))
    value * 2
  }
  let assert #(sandbox.Returned(values), sandbox) =
    sandbox.run(workflow, sandbox.sandbox())
  assert values == [2, 4, 6]
  assert sandbox.stdout == ["3", "2", "1"]
}

pub fn step_performs_only_the_first_operation_test() {
  let workflow = {
    use value <- system.then(system.env("EYG_UNSET_FOR_STEP_TEST"))
    use Nil <- system.map(system.stdout("after"))
    value
  }
  use next <- promise.map(system.step(workflow))
  let assert system.Stdout("after", resume) = next
  assert resume(Nil) == system.Done(None)
}
