import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import eyg_beam
import gleam/dict
import gleam/string
import gleeunit
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

const effects = [#("Add", #(t.Integer, t.Integer))]

pub fn check_returns_type_test() {
  assert eyg_beam.check("{a: 1}", effects, dict.new()) == Ok("{a: Integer}")
}

pub fn check_reports_parse_error_test() {
  let assert Error(message) = eyg_beam.check("{a: ", effects, dict.new())
  assert string.starts_with(message, "error: ")
}

pub fn check_reports_type_error_with_source_test() {
  let assert Error(message) =
    eyg_beam.check("!int_add(1, \"two\")", effects, dict.new())
  assert string.contains(message, "type mismatch")
  assert string.contains(message, "\"two\"")
}

pub fn check_rejects_effects_not_given_by_host_test() {
  let assert Error(message) =
    eyg_beam.check("perform Log(\"hi\")", effects, dict.new())
  assert string.contains(message, "Log")
}

pub fn run_answers_effects_with_handler_test() {
  let source = "let a = perform Add(2)\nperform Add(a)"
  let handler = fn(label, lift) {
    let assert #("Add", v.Integer(n)) = #(label, lift)
    v.Integer(n * 10)
  }
  assert eyg_beam.run(source, effects, dict.new(), handler)
    == Ok(v.Integer(200))
}

pub fn run_does_not_start_badly_typed_programs_test() {
  let handler = fn(_, _) { panic as "should not run" }
  let assert Error(_) =
    eyg_beam.run("perform Add(\"x\")", effects, dict.new(), handler)
}

pub fn run_with_standard_package_test() {
  let assert Ok(json) =
    simplifile.read("../../eyg_packages/standard/index.eyg.json")
  let assert Ok(standard) = eyg_beam.load_package(json)
  let packages = dict.from_list([#("standard", standard)])
  let source = "@standard.list.map([1, 2], (x) -> { perform Add(x) })"
  let handler = fn(_, lift) { lift }

  assert eyg_beam.check(source, effects, packages) == Ok("List(Integer)")
  assert eyg_beam.run(source, effects, packages, handler)
    == Ok(v.LinkedList([v.Integer(1), v.Integer(2)]))
}

pub fn missing_package_is_a_type_error_test() {
  let assert Error(message) =
    eyg_beam.check("@standard.list", effects, dict.new())
  assert string.contains(message, "@standard")
}

pub fn type_mismatch_names_given_and_expected_types_test() {
  let assert Error(message) =
    eyg_beam.check("perform Add(\"x\")", effects, dict.new())
  assert string.contains(message, "given: String expected: Integer")
}
