import eyg/cli/helpers
import eyg/cli/tui/completion
import eyg/cli/tui/editor
import eyg/cli/tui/highlight as h
import eyg/cli/tui/model
import eyg/cli/tui/shell
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/sandbox

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
  use #(events, progress) <- promise.await(shell.advance(effect, 1000.0))
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
    == [shell.Performed("StandardOut", "\"hello\"", "{}")]
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
  let ready = model.started(model.new("."), started())
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
  let #(model, commands) =
    model.discovered(model.started(model.new("."), started()), [
      "standard",
      "stats",
    ])
  assert commands == [model.Complete]
  let model = model.Model(..model, editor: editor.insert(model.editor, "@st"))
  let choices = completion.complete("@st", 3, model.packages, ".")
  let model = model.completed_choices(model, choices)
  let #(model, _) = model.key(model, "down")
  let #(model, _) = model.key(model, "tab")
  assert model.editor == editor.Editor("@stats", 6)
  assert model.choices == []
}
