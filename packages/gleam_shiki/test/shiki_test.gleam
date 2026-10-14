import gleam/javascript/promise
import gleam/list
import gleam/string
import gleeunit/should
import shiki
import simplifile

pub fn grammar_tokens_preserve_unicode_lines_and_colors_test() {
  let grammar =
    simplifile.read("../vscode-eyg/syntaxes/eyg.tmLanguage.json")
    |> should.be_ok
  use highlighter <- promise.map(shiki.create(grammar))
  let highlighter = should.be_ok(highlighter)
  let source = "let leaf = \"🌱緑\"\n!int_add(20, 22)"
  let highlighted =
    shiki.highlight(highlighter, source, "eyg", "github-dark") |> should.be_ok
  highlighted.lines
  |> list.map(fn(line) {
    line |> list.map(fn(token) { token.content }) |> string.concat
  })
  |> string.join("\n")
  |> should.equal(source)
  highlighted.lines
  |> list.flatten
  |> list.any(fn(token) { token.color != highlighted.foreground })
  |> should.be_true
}

pub fn invalid_grammar_returns_a_binding_error_test() {
  use highlighter <- promise.map(shiki.create("not JSON"))
  should.be_error(highlighter)
  Nil
}
