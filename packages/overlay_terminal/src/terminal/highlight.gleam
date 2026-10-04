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

pub type Token {
  Token(text: String, kind: String, color: String, start: Int, end: Int)
}

const pattern =
  "(//[^\\n]*|\"(?:\\\\[\\s\\S]|[^\"\\\\])*\"?|@[a-zA-Z0-9_:.-]+|#[a-zA-Z0-9]+|![a-z_][a-z0-9_]*|\\b(?:let|import|perform|handle|match)\\b|\\b[A-Z][a-zA-Z0-9_]*\\b|-?\\b\\d+\\b)"

pub fn tokens(source) {
  let assert Ok(regex) = regexp.from_string(pattern)
  split(regexp.split(regex, source), False, 0, []) |> list.reverse
}

fn split(parts, matched, offset, acc) {
  case parts {
    [] -> acc
    [part, ..rest] -> {
      let kind = case matched {
        True -> classify(part)
        False -> ""
      }
      let end = offset + { string.to_utf_codepoints(part) |> list.length }
      let acc = case part {
        "" -> acc
        _ -> [Token(part, kind, color(kind), offset, end), ..acc]
      }
      split(rest, !matched, end, acc)
    }
  }
}

fn classify(value) {
  case value {
    "//" <> _ -> "comment"
    "\"" <> _ -> "string"
    "@" <> _ | "#" <> _ -> "reference"
    "!" <> _ -> "builtin"
    _ -> {
      let assert Ok(number) = regexp.from_string("^-?[0-9]")
      let assert Ok(tag) = regexp.from_string("^[A-Z]")
      case regexp.check(number, value), regexp.check(tag, value) {
        True, _ -> "number"
        _, True -> "tag"
        _, _ -> "keyword"
      }
    }
  }
}

pub fn color(kind) {
  case kind {
    "comment" -> muted
    "string" | "char" -> accent
    "reference" | "builtin" | "symbol" -> blue
    "number" | "tag" | "class-name" -> orange
    "keyword" -> purple
    "important" -> red
    _ -> text
  }
}
