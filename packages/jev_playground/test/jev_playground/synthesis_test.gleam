import eyg/parser
import gleam/list
import gleam/option.{None}
import jev_playground/action as a
import jev_playground/environment
import jev_playground/synthesis
import morph/editable as e

fn parse(source) {
  let assert Ok(tree) = parser.all_from_string(source)
  e.from_annotated(tree)
}

fn script(source) {
  synthesis.script(parse(source), environment.browser())
}

fn builds(source) {
  let assert Ok(actions) = script(source)
  actions
}

pub fn a_function_is_built_top_down_test() {
  assert builds("(n) -> { !int_add(n, 1) }")
    == [
      a.Function("n"),
      a.Builtin("int_add"),
      a.Call,
      a.Variable("n"),
      a.Integer(1),
    ]
}

pub fn assignments_are_built_in_order_test() {
  assert builds("let x = 1\nlet y = \"a\"\nx")
    == [
      a.Assign("x"),
      a.Integer(1),
      a.Assign("y"),
      a.String("a"),
      a.Variable("x"),
    ]
}

pub fn records_create_every_field_at_once_test() {
  assert builds("{name: \"a\", age: 2}")
    == [a.Record(["name", "age"]), a.String("a"), a.Integer(2)]
}

pub fn lists_create_every_item_then_fill_them_test() {
  assert builds("[1, 2, 3]")
    == [
      a.List,
      a.InsertBefore(None),
      a.InsertBefore(None),
      a.Integer(1),
      a.Integer(2),
      a.Integer(3),
    ]
}

pub fn list_spread_test() {
  let assert Ok(_) = script("let rest = []\n[1, ..rest]")
}

pub fn match_branches_rename_their_parameters_test() {
  let actions =
    builds(
      "(r) -> {\n  match r {\n    Ok(value) -> { value }\n    Error(_) -> { 0 }\n  }\n}",
    )
  assert list.contains(actions, a.Match(["Ok", "Error"]))
  assert list.contains(actions, a.Rename("value"))
}

pub fn match_with_otherwise_test() {
  let assert Ok(_) =
    script(
      "(r) -> {\n  match r {\n    Ok(value) -> { value }\n    | (_) -> { 0 }\n  }\n}",
    )
}

pub fn match_without_subject_test() {
  let assert Ok(_) =
    script("match {\n  Ok(value) -> { value }\n  Error(_) -> { 0 }\n}")
}

pub fn handle_test() {
  let assert Ok(actions) =
    script(
      "handle GitHub((operation, resume) -> { Error(operation.path) }, (_) -> { perform GitHub({path: \"/\"}) })",
    )
  assert list.contains(actions, a.Handle("GitHub"))
  assert list.contains(actions, a.Rename("operation"))
}

pub fn destructured_patterns_test() {
  let assert Ok(actions) = script("let {a, b: c} = {a: 1, b: 2}\nc")
  assert list.contains(actions, a.Destructure([#("a", "a"), #("b", "c")]))
  let assert Ok(_) = script("({key, value}) -> { key }")
}

pub fn selecting_fields_test() {
  assert builds("let user = {name: \"a\"}\nuser.name")
    == [
      a.Assign("user"),
      a.Record(["name"]),
      a.String("a"),
      a.Variable("user"),
      a.Select("name"),
    ]
}

pub fn calls_with_more_arguments_than_known_insert_holes_test() {
  let assert Ok(_) = script("(f) -> { f(1, 2) }")
}
