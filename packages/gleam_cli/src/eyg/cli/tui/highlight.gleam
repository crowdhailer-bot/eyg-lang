//// Colours of the tui and of EYG source text.

import gleam/list
import gleam/regexp
import gleam/string

pub const bg = "#141414"

pub const panel = "#1e1e1e"

pub const text = "#eeeeee"

pub const muted = "#808080"

pub const accent = "#a9c9a0"

pub const blue = "#9bb5d6"

pub const orange = "#e5c07b"

pub const red = "#e06c75"

pub const purple = "#c792ea"

const pattern =
  "(//[^\\n]*|\"(?:\\\\[\\s\\S]|[^\"\\\\])*\"?|@[a-zA-Z0-9_:.-]+|#[a-zA-Z0-9]+|![a-z_][a-z0-9_]*|\\b(?:let|import|perform|handle|match)\\b|\\b[A-Z][a-zA-Z0-9_]*\\b|-?\\b\\d+\\b)"

/// Highlighted source as lines of text and colour.
pub fn lines(source) -> List(List(#(String, String))) {
  let assert Ok(regex) = regexp.from_string(pattern)
  // Split alternates between plain text and matched tokens.
  let #(_, current, done) =
    list.fold(regexp.split(regex, source), #(False, [], []), fn(acc, part) {
      let #(matched, current, done) = acc
      let color = case matched {
        True -> classify(part)
        False -> text
      }
      let assert [first, ..rest] = string.split(part, "\n")
      let current = append(current, first, color)
      let #(current, done) =
        list.fold(rest, #(current, done), fn(acc, line) {
          let #(current, done) = acc
          #(append([], line, color), [list.reverse(current), ..done])
        })
      #(!matched, current, done)
    })
  list.reverse([list.reverse(current), ..done])
}

fn append(line, text, color) {
  case text {
    "" -> line
    _ -> [#(text, color), ..line]
  }
}

pub fn classify(token) {
  case token {
    "//" <> _ -> muted
    "\"" <> _ -> accent
    "@" <> _ | "#" <> _ | "!" <> _ -> blue
    "let" | "import" | "perform" | "handle" | "match" -> purple
    _ -> orange
  }
}
