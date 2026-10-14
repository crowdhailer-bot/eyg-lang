import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import terminal/app as a
import terminal/completion as c
import terminal/highlight as h
import terminal/protocol as p

fn ready() {
  a.update(a.new(False), a.Received(p.Ready(["standard"]))).0
}

pub fn late_completion_cannot_replace_current_choices_test() {
  let #(first, _) = a.update(ready(), a.Changed("@s", 2))
  let #(second, _) = a.update(first, a.Changed("@sta", 4))
  let #(late, _) =
    a.update(
      second,
      a.CompletedChoices(first.completion_revision, [
        c.Completion("stale", "", "stale", 0, 2),
      ]),
    )
  late.choices |> should.equal([])
  late.source |> should.equal("@sta")
}

pub fn prompted_input_restores_the_draft_and_sends_only_the_reply_test() {
  let #(draft, _) = a.update(ready(), a.Changed("next expression", 15))
  let #(prompted, _) = a.update(draft, a.Received(p.Prompt(1, "Name?")))
  let #(answered, _) = a.update(prompted, a.Changed("Corin", 5))
  let #(restored, commands) = a.update(answered, a.Submit)
  restored.source |> should.equal("next expression")
  restored.prompt |> should.equal(None)
  commands
  |> should.equal([
    a.Send(p.Reply("Corin")),
    a.Editor("next expression", False, None),
  ])
}

pub fn structural_parse_failure_restores_text_and_allows_retry_test() {
  let #(draft, _) = a.update(ready(), a.Changed("let x =", 7))
  let #(editing, enter) = a.update(draft, a.SwitchMode)
  enter
  |> should.equal([
    a.Editor("", False, None),
    a.Send(p.Structure(p.Enter(Some("let x =")))),
  ])
  let #(failed, _) =
    a.update(editing, a.Received(p.Failure(0, "Incomplete expression")))
  failed.structural |> should.be_false
  failed.source |> should.equal("let x =")
  failed.imported_draft |> should.equal(None)
}

pub fn stream_chunks_keep_tool_details_and_assistant_identity_test() {
  let #(model, _) = a.update(a.new(True), a.Received(p.Tool(-1, "run", "42")))
  let #(model, _) = a.update(model, a.ToggleCode(-1))
  let #(model, _) = a.update(model, a.Received(p.Assistant(-2, "Hello ")))
  let #(model, _) = a.update(model, a.Received(p.Assistant(-2, "world")))
  a.find_entry(model, -1)
  |> should.be_ok
  |> fn(entry) { entry.code_expanded |> should.be_true }
  a.find_entry(model, -2)
  |> should.be_ok
  |> fn(entry) { entry.output |> should.equal("Hello world") }
  list.length(model.entries) |> should.equal(2)
}

pub fn unicode_completion_preserves_text_on_both_sides_test() {
  let prefix = "let banner = \"🌱緑é\" "
  let source = prefix <> "@sta.integer.add"
  let cursor = string.length(prefix <> "@sta")
  use choices <- promise.map(c.complete(source, cursor, ["standard"], "."))
  let choice = list.first(choices) |> should.be_ok
  c.apply(source, choice)
  |> should.equal(#(prefix <> "@standard.integer.add", prefix <> "@standard"))
}

pub fn file_completion_replaces_only_the_import_path_test() {
  let source = "let a = import \"./src/terminal/comp"
  use choices <- promise.map(c.complete(source, string.length(source), [], "."))
  let choice = list.first(choices) |> should.be_ok
  c.apply(source, choice).0
  |> should.equal("let a = import \"./src/terminal/completion.gleam")
}

pub fn highlight_preserves_source_and_uses_native_codepoint_offsets_test() {
  let source = "let leaf = \"🌱é\" // comment\n!int_add(-2, 42)"
  let tokens = h.tokens(source)
  list.map(tokens, fn(token) { token.text })
  |> string.join("")
  |> should.equal(source)
  let builtin =
    list.find(tokens, fn(token) { token.kind == "builtin" }) |> should.be_ok
  builtin.text |> should.equal("!int_add")
  builtin.start |> should.equal(28)
  list.last(tokens)
  |> should.be_ok
  |> fn(token) { token.end |> should.equal(44) }
  h.tokens("letter") |> list.map(fn(token) { token.kind }) |> should.equal([""])
}
