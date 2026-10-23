import eyg/cli/helpers
import eyg/cli/tui/completion
import eyg/cli/tui/editor
import eyg/cli/tui/highlight as h
import eyg/cli/tui/host
import eyg/cli/tui/model
import eyg/cli/tui/projection
import eyg/cli/tui/shell
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/sandbox
import morph/editable
import morph/render

fn started() {
  let assert Ok(started) = shell.start(None, helpers.config) |> in_sandbox
  started
}

fn in_sandbox(effect) {
  let assert #(sandbox.Returned(value), _) =
    sandbox.run(effect, sandbox.sandbox())
  value
}

fn advanced(effect) {
  use stepped <- promise.await(host.advance(effect, 1000.0))
  let assert Ok(#(events, progress)) = stepped
  case progress {
    shell.Paused(effect) -> {
      use #(more, progress) <- promise.map(advanced(effect))
      #(list.append(events, more), progress)
    }
    _ -> promise.resolve(#(events, progress))
  }
}

pub fn evaluation_reports_output_results_and_effects_test() {
  let effect = shell.evaluate(started(), "perform StandardOut(\"hello\")")
  use #(events, progress) <- promise.map(advanced(effect))
  assert events == [shell.Output("hello", False)]
  let assert shell.Finished(evaluated) = progress
  assert evaluated.results == [Ok("{}")]
  assert evaluated.performed
    == [shell.Performed("StandardOut", "\"hello\"", "{}", None)]
}

pub fn standard_input_asks_and_resumes_the_evaluation_test() {
  let source =
    "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }"
  use #(_, progress) <- promise.await(
    advanced(shell.evaluate(started(), source)),
  )
  let assert shell.Asking("Standard input", resume) = progress
  use #(_, progress) <- promise.map(advanced(resume("typed")))
  let assert shell.Finished(evaluated) = progress
  assert evaluated.results == [Ok("Ok(\"typed\")")]
}

pub fn incomplete_input_continues_on_the_next_line_test() {
  use #(_, progress) <- promise.await(
    advanced(shell.evaluate(started(), "let y = {")),
  )
  let assert shell.Finished(evaluated) = progress
  assert evaluated.shell.pending == "let y = {"
  use #(_, progress) <- promise.map(
    advanced(shell.evaluate(evaluated.shell, "a: 1 }\ny.a")),
  )
  let assert shell.Finished(evaluated) = progress
  assert evaluated.results == [Ok("1")]
}

pub fn a_prompt_keeps_the_draft_and_answers_only_the_reply_test() {
  let typed = fn(model, text) {
    string.to_graphemes(text)
    |> list.fold(model, fn(model, key) { model.key(model, key).0 })
  }
  let ready = model.started(model.new(".", False), started())
  let drafted = typed(ready, "next")
  let asked = model.asked(drafted, "Name?")
  assert asked.prompt == Some(#("Name?", drafted.editor))
  let #(answered, commands) = model.key(typed(asked, "Ada"), "enter")
  assert commands == [model.Answer("Ada")]
  assert answered.editor.text == "next"
  assert answered.prompt == None
}

pub fn editor_moves_by_words_and_lines_test() {
  let key = fn(editor, key) {
    let assert editor.Edited(editor) = editor.key(editor, key)
    editor
  }
  let edited =
    editor.new()
    |> editor.insert("let a = 1\nlet b")
    |> key("ctrl+w")
    |> key("up")
    |> key("ctrl+k")
  assert edited.text == "let \nlet "
  assert editor.key(edited, "enter") == editor.Submitted
  assert key(edited, "alt+\r").text == "let \n\nlet "
}

pub fn highlighted_lines_split_tokens_at_newlines_test() {
  h.lines("let a = \"x\ny\"\n!int_add(1, 2)")
  |> list.map(fn(line) { list.map(line, fn(part) { part.0 }) |> string.concat })
  |> fn(lines) {
    assert lines == ["let a = \"x", "y\"", "!int_add(1, 2)"]
  }
  assert h.lines("") == [[]]
}

pub fn unicode_completion_preserves_text_on_both_sides_test() {
  let prefix = "let banner = \"🌱緑é\" "
  let source = prefix <> "@sta.integer.add"
  let cursor = string.length(prefix <> "@sta")
  let assert [choice, ..] =
    completion.complete(source, cursor, ["standard"], ".")
  assert completion.apply(source, choice)
    == #(prefix <> "@standard.integer.add", prefix <> "@standard")
}

pub fn file_completion_replaces_only_the_import_path_test() {
  let source = "let a = import \"./src/eyg/cli/tui/compl"
  let assert [choice] =
    completion.complete(source, string.length(source), [], ".")
  assert completion.apply(source, choice).0
    == "let a = import \"./src/eyg/cli/tui/completion.gleam"
}

pub fn tab_accepts_the_chosen_completion_test() {
  let model = model.started(model.new(".", False), started())
  let model =
    model.Model(
      ..model,
      packages: ["standard", "stats"],
      editor: editor.insert(model.editor, "@st"),
    )
  let choices = completion.complete("@st", 3, model.packages, ".")
  let model = model.completed_choices(model, choices)
  let #(model, _) = model.key(model, "down")
  let #(model, _) = model.key(model, "tab")
  assert model.editor == editor.Editor("@stats", 6, False)
  assert model.choices == []
}

fn keys(state, keys) {
  list.fold(keys, state, fn(state, key) {
    let #(model, commands) = state
    let #(model, more) = model.key(model, key)
    #(model, list.append(commands, more))
  })
}

fn typed(state, text) {
  keys(state, string.to_graphemes(text))
}

/// Run the evaluation a command asks for and complete it.
fn evaluated(state: #(model.Model, List(model.Command))) {
  let #(model, commands) = state
  let assert Ok(model.Evaluate(id, code)) =
    list.find(commands, fn(command) {
      case command {
        model.Evaluate(..) -> True
        _ -> False
      }
    })
  let assert Some(current) = model.shell
  let effect = case code {
    model.Text(source) -> shell.evaluate(current, source)
    model.Ir(code) -> shell.evaluate_ir(current, code)
  }
  use #(_, progress) <- promise.map(advanced(effect))
  let assert shell.Finished(evaluated) = progress
  model.completed(model, id, evaluated, 0.0)
}

fn structure_text(model: model.Model) {
  let assert Some(structure) = model.structure
  model.projection_text(structure)
}

fn ready() {
  #(model.started(model.new(".", False), started()), [])
}

pub fn structural_edits_undo_and_return_to_earlier_structures_test() {
  let #(model, _) =
    typed(ready(), "!int_add(20, 22)")
    |> keys(["f2", "right", "right", "n"])
  assert model.input(model) |> option.map(fn(input) { input.label })
    == Some("insert integer")
  assert model.editor == editor.Editor("20", 2, True)
  let #(model, _) = typed(#(model, []), "40") |> keys(["enter"])
  assert structure_text(model) == "!int_add(40, 22)"
  let #(model, _) = keys(#(model, []), ["z"])
  assert structure_text(model) == "!int_add(20, 22)"
  let state = keys(#(model, []), ["Z", "enter"])
  use #(model, _) <- promise.map(evaluated(state))
  let assert Ok(entry) = model.find(model, 1)
  assert entry.results == [Ok("62")]
  assert structure_text(model) == "Vacant"
  let #(model, _) = keys(#(model, []), ["up"])
  assert structure_text(model) == "!int_add(40, 22)"
  let #(model, _) = keys(#(model, []), ["down"])
  assert structure_text(model) == "Vacant"
}

pub fn copied_binary_values_survive_and_are_typed_in_text_test() {
  let #(model, commands) = keys(ready(), ["f2", "b", "y"])
  let assert Ok(model.Copy(copied)) = list.last(commands)
  assert string.contains(copied, "\"0\"")
  let #(model, _) = keys(#(model, []), ["d", "Y", "e"])
  let state = typed(#(model, []), "bytes") |> keys(["enter", "enter"])
  use #(model, _) <- promise.await(evaluated(state))
  let state =
    keys(#(model, []), ["f2"]) |> typed("/type bytes") |> keys(["enter"])
  use #(model, _) <- promise.map(evaluated(state))
  let assert Ok(entry) = model.find(model, 2)
  let assert [Ok(type_)] = entry.results
  assert string.contains(type_, "Binary")
}

pub fn failed_runs_and_invalid_answers_keep_the_structure_test() {
  let state = typed(ready(), "!int_add(20, \"wrong\")") |> keys(["f2", "enter"])
  use #(model, _) <- promise.await(evaluated(state))
  let assert Ok(model.Entry(results: [Error(_)], ..)) = model.find(model, 1)
  assert structure_text(model) == "!int_add(20, \"wrong\")"
  let #(model, _) = model.click(model, model.Focus([2]))
  let #(model, _) =
    keys(#(model, []), ["n"]) |> typed("invalid") |> keys(["enter"])
  assert model.status == "Enter an integer"
  let state =
    keys(#(model, []), ["ctrl+u"]) |> typed("22") |> keys(["enter", "enter"])
  use #(model, _) <- promise.map(evaluated(state))
  let assert Ok(entry) = model.find(model, 2)
  assert entry.results == [Ok("42")]
}

fn drawn(exp) {
  projection.project(render.top(exp, [])) |> projection.text
}

/// A nested block is drawn as a block in braces, not as a function.
pub fn nested_block_keeps_its_braces_test() {
  let block = ir.block([#("a", ir.integer(1))], ir.variable("a"))
  let exp =
    ir.call(ir.variable("f"), [block, ir.integer(2)])
    |> editable.from_annotated
  assert drawn(exp) == "f({ ... }, 2)"
  assert drawn(editable.open_all(exp))
    == "f(\n  {\n    let a = 1\n    a\n  },\n  2,\n)"
}

pub fn runaway_evaluation_stops_at_the_reduction_limit_test() {
  let source = "let forever = (f) -> { f(f) } forever(forever)"
  use #(_, progress) <- promise.map(advanced(shell.evaluate(started(), source)))
  let assert shell.Finished(evaluated) = progress
  let assert [Error(reason)] = evaluated.results
  assert string.contains(reason, "ExecutionLimit")
}
