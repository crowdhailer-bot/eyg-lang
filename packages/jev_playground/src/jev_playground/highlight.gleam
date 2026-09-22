//// Colour for the EYG a program is written in: the tokens the parser
//// distinguishes, and the selection marked with « and ».

import gleam/list
import gleam/regexp
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element, text}
import lustre/element/html as h

/// Split out the selection marked with « and » and highlight the rest.
pub fn highlight_program(code) -> List(Element(a)) {
  case string.split_once(code, "«") {
    Ok(#(before, rest)) ->
      case split_selection(rest) {
        Ok(#(selected, after)) ->
          list.flatten([
            highlight(before),
            [h.span([a.class("selection")], highlight(selected))],
            highlight(after),
          ])
        Error(Nil) -> highlight(code)
      }
    Error(Nil) -> highlight(code)
  }
}

// The last » closes the selection, strings may contain the markers.
fn split_selection(rest) {
  case string.split(rest, "»") |> list.reverse {
    [after, ..selected] if selected != [] ->
      Ok(#(string.join(list.reverse(selected), "»"), after))
    _ -> Error(Nil)
  }
}

const keywords = ["let", "match", "perform", "handle", "import"]

pub fn highlight(code) -> List(Element(a)) {
  let assert Ok(re) =
    regexp.from_string(
      "\"(?:[^\"\\\\]|\\\\.)*\"|![a-z_][a-z0-9_]*|[a-z_][a-z0-9_]*|[A-Z][A-Za-z0-9]*|-?[0-9]+|\\?|\\s+|.",
    )
  regexp.scan(re, code)
  |> list.map(fn(match) {
    let token = match.content
    let class = case token {
      "\"" <> _ -> "string"
      "!" <> _ -> "builtin"
      "?" -> "hole"
      _ ->
        case list.contains(keywords, token) {
          True -> "keyword"
          False -> classify(token)
        }
    }
    case class {
      "" -> text(token)
      _ -> h.span([a.class(class)], [text(token)])
    }
  })
}

fn classify(token) {
  let assert Ok(tag) = regexp.from_string("^[A-Z]")
  let assert Ok(number) = regexp.from_string("^-?[0-9]")
  case regexp.check(tag, token), regexp.check(number, token) {
    True, _ -> "tag"
    _, True -> "number"
    _, _ -> ""
  }
}
