import eyg/ir/tree as ir
import eyg/parser
import gleam/list
import gleam/option.{None}
import gleam/string
import morph/editable as e
import morph/projection as p
import morph/text
import simplifile

fn parse(source) {
  let assert Ok(tree) = parser.all_from_string(source)
  e.from_annotated(tree)
}

fn round_trip(source) {
  assert text.print(parse(source)) == source
}

const cursor = text.Mark("«", "»")

fn focus(source, path) {
  text.projection(p.focus_at(parse(source), path), cursor)
}

pub fn assignments_print_on_separate_lines_test() {
  round_trip("let x = 5\nlet y = \"hi\"\nx")
}

pub fn function_with_short_body_is_inline_test() {
  round_trip("(x, y) -> { !int_add(x, y) }")
}

pub fn function_with_block_body_is_indented_test() {
  round_trip("let f = (x) -> {\n  let y = !int_add(x, 1)\n  y\n}\nf(1)")
}

pub fn destructure_uses_shorthand_test() {
  round_trip("let {name, age: n} = person\nname")
}

pub fn match_prints_branches_on_lines_test() {
  round_trip(
    "match result {\n  Ok(value) -> { value }\n  Error(_) -> { 0 }\n  | (_) -> { -1 }\n}",
  )
}

pub fn match_without_subject_is_a_function_test() {
  round_trip(
    "let f = match {\n  Ok(value) -> { value }\n  | (_) -> { -1 }\n}\nf",
  )
}

pub fn records_and_lists_test() {
  round_trip("{name: \"Alice\", age: 30, ..person}")
  round_trip("[1, 2, ..rest]")
  round_trip("{name, email: \"a@b\"}")
}

pub fn effects_and_builtins_test() {
  round_trip("perform Log(\"hi\")")
  round_trip("handle Log")
  round_trip("!string_append(\"a\", \"b\")")
}

pub fn references_test() {
  round_trip("@standard.list")
  round_trip("@http:3")
  round_trip("import \"./x.eyg\"")
}

pub fn strings_are_escaped_test() {
  round_trip("\"say \\\"hi\\\"\\n\\ttab \\\\ \"")
}

pub fn long_calls_break_one_argument_per_line_test() {
  round_trip(
    "some_function(\n  \"a long argument value\",\n  \"another long argument value\",\n  \"third argument\"\n)",
  )
}

pub fn a_final_function_argument_opens_on_the_same_line_test() {
  round_trip(
    "list.map(items, (item) -> {\n  let doubled = !int_multiply(item, 2)\n  doubled\n})",
  )
}

pub fn nested_block_value_is_indented_test() {
  round_trip("let x =\n  let y = 1\n  y\nx")
}

pub fn printed_text_parses_to_the_same_tree_test() {
  let source =
    "let http = @http\nlet get = (path) -> {\n  let op = http.operation.get(path)\n  http.dispatch(op, http.origin.https(\"api.github.com\"))\n}\n{get, tests: [{name: \"one\", test: (_) -> { !equal(1, 1) }}]}"
  let editable = parse(source)
  let assert Ok(reparsed) = parser.all_from_string(text.print(editable))
  assert ir.clear_annotation(reparsed)
    == ir.clear_annotation(e.to_annotated(editable, []))
}

pub fn vacant_prints_as_question_mark_test() {
  let source = e.Block([#(e.Bind("x"), e.Vacant)], e.Vacant, True)
  assert text.print(source) == "let x = ?\n?"
}

pub fn binary_prints_as_builtin_call_test() {
  assert text.print(e.Binary(<<1, 255>>)) == "!binary_from_integers([1, 255])"
}

pub fn focus_on_value_is_marked_test() {
  assert focus("let x = 5\nx", [0, 1]) == "let x = «5»\nx"
}

pub fn focus_on_statement_marks_the_assignment_test() {
  assert focus("let x = 5\nx", [0]) == "«let x = 5»\nx"
}

pub fn focus_on_pattern_marks_the_variable_test() {
  assert focus("let x = 5\nx", [0, 0]) == "let «x» = 5\nx"
}

pub fn focus_on_destructured_field_test() {
  assert focus("let {a: b} = r\nb", [0, 0, 1]) == "let {a: «b»} = r\nb"
  assert focus("let {a} = r\na", [0, 0, 0]) == "let {«a»: a} = r\na"
}

pub fn focus_on_argument_test() {
  assert focus("f(x, y)", [2]) == "f(x, «y»)"
}

pub fn focus_on_record_label_breaks_shorthand_test() {
  assert focus("{name}", [0]) == "{«name»: name}"
}

pub fn focus_on_match_label_test() {
  assert focus("match r {\n  Ok(v) -> { v }\n}", [1])
    == "match r {\n  «Ok»(v) -> { v }\n}"
}

pub fn focus_on_select_label_test() {
  assert focus("user.name", [1]) == "user.«name»"
}

pub fn focus_on_whole_program_test() {
  assert focus("let x = 5\nx", []) == "«let x = 5\nx»"
}

pub fn several_nodes_can_be_marked_test() {
  let source = e.Call(e.Variable("f"), [e.Vacant, e.Vacant])
  let marks = [#([1], text.Mark("«1:", "»")), #([2], text.Mark("«2:", "»"))]
  assert text.marked(source, marks) == "f(«1:?», «2:?»)"
}

pub fn empty_record_and_list_test() {
  assert text.print(e.Record([], None)) == "{}"
  assert text.print(e.List([], None)) == "[]"
}

pub fn every_eyg_package_file_round_trips_test() {
  let assert Ok(files) = simplifile.get_files("../../eyg_packages")
  let files = list.filter(files, string.ends_with(_, ".eyg"))
  assert files != []
  list.each(files, fn(file) {
    let assert Ok(source) = simplifile.read(file)
    let assert Ok(tree) = parser.all_from_string(source)
    let editable = e.from_annotated(tree)
    let printed = text.print(editable)
    let reparsed = case parser.all_from_string(printed) {
      Ok(reparsed) -> reparsed
      Error(reason) -> panic as { file <> " " <> string.inspect(reason) }
    }
    assert #(file, ir.clear_annotation(reparsed))
      == #(file, ir.clear_annotation(e.to_annotated(editable, [])))
  })
}

pub fn separators_count_towards_the_line_width_test() {
  round_trip(
    "{\n  method: GET({}),\n  path,\n  query: None({}),\n  headers: [],\n  body: !string_to_binary(\"\")\n}",
  )
}
