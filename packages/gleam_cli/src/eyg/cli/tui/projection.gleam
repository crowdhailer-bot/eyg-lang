//// Morph's projection laid out as lines of styled text.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import morph/frame

/// Text with the token class it is coloured by, whether it is selected or has
/// an error, and the path of the expression a click focuses.
pub type Chunk {
  Chunk(
    text: String,
    token: String,
    selected: Bool,
    error: Bool,
    path: Option(List(Int)),
  )
}

type Lines {
  Lines(done: List(List(Chunk)), current: List(Chunk))
}

pub fn project(nodes: List(frame.Node)) -> List(List(Chunk)) {
  let inherited = Chunk("", "", False, False, None)
  let lines =
    list.fold(nodes, Lines([], []), fn(lines, node) {
      visit(node, inherited, 0, lines)
    })
  let lines = case lines.current {
    [] -> lines.done
    _ -> [list.reverse(lines.current), ..lines.done]
  }
  case lines {
    [] -> [[]]
    _ -> list.reverse(lines)
  }
}

pub fn text(lines) {
  list.map(lines, fn(line) {
    list.map(line, fn(chunk: Chunk) { chunk.text }) |> string.concat
  })
  |> string.join("\n")
}

fn newline(lines: Lines) {
  case lines.current {
    [] -> lines
    current -> Lines([list.reverse(current), ..lines.done], [])
  }
}

fn visit(
  node: frame.Node,
  inherited: Chunk,
  indent: Int,
  lines: Lines,
) -> Lines {
  case node {
    frame.Text(content) ->
      append_parts(string.split(content, "\n"), inherited, indent, lines)
    frame.Span(attributes, children) -> {
      let #(next, indent) = apply(attributes, inherited, indent)
      visit_children(children, next, indent, lines)
    }
    frame.Div(attributes, children) -> {
      let #(next, indent) = apply(attributes, inherited, indent)
      newline(lines)
      |> visit_children(children, next, indent, _)
      |> newline
    }
  }
}

fn apply(attributes, inherited: Chunk, indent) {
  list.fold(attributes, #(inherited, indent), fn(state, attribute) {
    let #(chunk, indent) = state
    case attribute {
      frame.Class(class) -> #(
        Chunk(..chunk, token: string.replace(class, "token ", "")),
        indent,
      )
      frame.Path(path) -> #(Chunk(..chunk, path: Some(path)), indent)
      frame.Title(_) -> state
      frame.Indent -> #(chunk, indent + 2)
      frame.Focus -> #(Chunk(..chunk, selected: True), indent)
      frame.Problem -> #(Chunk(..chunk, error: True), indent)
    }
  })
}

fn visit_children(
  nodes: List(frame.Node),
  inherited: Chunk,
  indent: Int,
  lines: Lines,
) -> Lines {
  list.fold(nodes, lines, fn(lines, child) {
    visit(child, inherited, indent, lines)
  })
}

fn append_parts(parts, inherited, indent, lines: Lines) {
  case parts {
    [] -> lines
    [part, ..rest] -> {
      let current = case lines.current, part, indent {
        [], "", _ -> []
        [], _, 0 -> []
        [], _, _ -> [
          Chunk(" " |> string.repeat(indent), "", False, False, None),
        ]
        current, _, _ -> current
      }
      let current = case part {
        "" -> current
        _ -> [Chunk(..inherited, text: part), ..current]
      }
      case rest {
        [] -> Lines(..lines, current:)
        _ ->
          append_parts(
            rest,
            inherited,
            indent,
            Lines([list.reverse(current), ..lines.done], []),
          )
      }
    }
  }
}
