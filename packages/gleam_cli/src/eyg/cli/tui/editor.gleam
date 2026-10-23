//// The text being written, with readline's keys under étui's key names.
//// The cursor counts graphemes. Selected text is replaced by what is typed next.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type Editor {
  Editor(text: String, cursor: Int, selected: Bool)
}

/// What a key did to the editor.
pub type Outcome {
  Edited(Editor)
  Submitted
  Ignored
}

pub fn new() {
  Editor("", 0, False)
}

/// Text with the cursor at its end.
pub fn from(text, selected) {
  Editor(text, string.length(text), selected)
}

pub fn insert(editor: Editor, text: String) {
  let editor = case editor.selected {
    True -> new()
    False -> editor
  }
  let before = string.slice(editor.text, 0, editor.cursor)
  let after = string.drop_start(editor.text, editor.cursor)
  Editor(before <> text <> after, editor.cursor + string.length(text), False)
}

pub fn key(editor: Editor, key: String) -> Outcome {
  case key {
    "enter" -> Submitted
    "alt+enter" | "alt+\r" | "alt+\n" -> Edited(insert(editor, "\n"))
    "left" | "ctrl+b" -> Edited(move(editor, editor.cursor - 1))
    "right" | "ctrl+f" -> Edited(move(editor, editor.cursor + 1))
    "up" -> Edited(vertical(editor, -1))
    "down" -> Edited(vertical(editor, 1))
    "home" | "ctrl+a" -> Edited(move(editor, line_start(editor)))
    "end" -> Edited(move(editor, line_end(editor)))
    "ctrl+left" | "alt+b" -> Edited(move(editor, word_start(editor)))
    "ctrl+right" | "alt+f" -> Edited(move(editor, word_end(editor)))
    "backspace" -> Edited(delete(editor, editor.cursor - 1, editor.cursor))
    "delete" | "ctrl+d" ->
      Edited(delete(editor, editor.cursor, editor.cursor + 1))
    "ctrl+w" | "alt+backspace" | "alt+\u{7f}" ->
      Edited(delete(editor, word_start(editor), editor.cursor))
    "ctrl+k" -> Edited(delete(editor, editor.cursor, line_end(editor)))
    "ctrl+u" -> Edited(delete(editor, line_start(editor), editor.cursor))
    _ ->
      case printable(key) {
        True -> Edited(insert(editor, key))
        False -> Ignored
      }
  }
}

fn printable(key) {
  case string.to_graphemes(key), string.to_utf_codepoints(key) {
    [_], [first, ..] -> string.utf_codepoint_to_int(first) >= 32
    _, _ -> False
  }
}

fn move(editor: Editor, cursor) {
  let cursor = int.clamp(cursor, 0, string.length(editor.text))
  Editor(..editor, cursor:, selected: False)
}

fn delete(editor: Editor, from, to) {
  use <- bool.guard(editor.selected, new())
  let from = int.max(0, from)
  let to = int.min(to, string.length(editor.text))
  case from < to {
    False -> editor
    True ->
      Editor(
        string.slice(editor.text, 0, from) <> string.drop_start(editor.text, to),
        from,
        False,
      )
  }
}

/// Line and column of the cursor, both counted in graphemes.
pub fn position(editor: Editor) -> #(Int, Int) {
  let lines = string.slice(editor.text, 0, editor.cursor) |> string.split("\n")
  let column = list.last(lines) |> result.unwrap("") |> string.length
  #(list.length(lines) - 1, column)
}

fn vertical(editor: Editor, delta) {
  let #(line, column) = position(editor)
  let lines = string.split(editor.text, "\n")
  let target = line + delta
  case target < 0 || target >= list.length(lines) {
    True -> editor
    False -> {
      let offset =
        lines
        |> list.take(target)
        |> list.fold(0, fn(total, line) { total + string.length(line) + 1 })
      let length = case list.drop(lines, target) {
        [line, ..] -> string.length(line)
        [] -> 0
      }
      move(editor, offset + int.min(column, length))
    }
  }
}

fn line_start(editor: Editor) {
  let #(_, column) = position(editor)
  editor.cursor - column
}

fn line_end(editor: Editor) {
  let rest = string.drop_start(editor.text, editor.cursor)
  case string.split_once(rest, "\n") {
    Ok(#(line, _)) -> editor.cursor + string.length(line)
    Error(Nil) -> editor.cursor + string.length(rest)
  }
}

fn word_start(editor: Editor) {
  let before =
    string.slice(editor.text, 0, editor.cursor)
    |> string.to_graphemes
    |> list.reverse
  editor.cursor - word(before)
}

fn word_end(editor: Editor) {
  editor.cursor
  + word(string.drop_start(editor.text, editor.cursor) |> string.to_graphemes)
}

/// Graphemes up to the end of the next word, skipping spaces before it.
fn word(graphemes) {
  let spaces = list.take_while(graphemes, is_space) |> list.length
  let letters =
    list.drop(graphemes, spaces)
    |> list.take_while(fn(grapheme) { !is_space(grapheme) })
    |> list.length
  spaces + letters
}

fn is_space(grapheme) {
  grapheme == " " || grapheme == "\n" || grapheme == "\t"
}
