//// Adapt Morph's existing Lustre projection; do not print the AST again.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre/vdom/vattr
import lustre/vdom/vnode as v
import terminal/protocol as p

type Lines {
  Lines(done: List(List(p.Chunk)), current: List(p.Chunk))
}

pub fn project(elements: List(v.Element(a))) -> List(List(p.Chunk)) {
  let inherited = p.Chunk("", "", False, False, None)
  let lines =
    list.fold(elements, Lines([], []), fn(lines, node) {
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
    list.map(line, fn(chunk: p.Chunk) { chunk.text }) |> string.concat
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
  node: v.Element(a),
  inherited: p.Chunk,
  indent: Int,
  lines: Lines,
) -> Lines {
  case node {
    v.Text(content:, ..) ->
      append_parts(string.split(content, "\n"), inherited, indent, lines)
    v.Fragment(children:, ..) ->
      visit_children(children, inherited, indent, lines)
    v.Element(tag:, attributes:, children:, ..) -> {
      let style = attr(attributes, "style") |> result.unwrap("")
      let token = case attr(attributes, "class") {
        Ok(value) -> string.replace(value, "token ", "")
        _ -> inherited.token
      }
      let path = case attr(attributes, "data-rev") {
        Ok("") -> Some([])
        Ok(value) ->
          Some(
            string.split(value, ",")
            |> list.filter_map(int.parse)
            |> list.reverse,
          )
        Error(_) -> inherited.path
      }
      let next =
        p.Chunk(
          ..inherited,
          token:,
          path:,
          selected: inherited.selected
            || string.contains(style, "background-color"),
          error: inherited.error || string.contains(style, "underline"),
        )
      let indent =
        indent
        + case string.contains(style, "padding-left") {
          True -> 2
          False -> 0
        }
      let lines = case tag {
        "div" -> newline(lines)
        _ -> lines
      }
      let lines = visit_children(children, next, indent, lines)
      case tag {
        "div" -> newline(lines)
        _ -> lines
      }
    }
    v.Map(child:, ..) -> visit(child, inherited, indent, lines)
    v.Memo(view:, ..) -> visit(view(), inherited, indent, lines)
    v.UnsafeInnerHtml(..) -> lines
  }
}

fn visit_children(
  nodes: List(v.Element(a)),
  inherited: p.Chunk,
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
          p.Chunk(" " |> string.repeat(indent), "", False, False, None),
        ]
        current, _, _ -> current
      }
      let current = case part {
        "" -> current
        _ -> [p.Chunk(..inherited, text: part), ..current]
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

fn attr(attributes, name) {
  list.find_map(attributes, fn(attribute) {
    case attribute {
      vattr.Attribute(name: key, value:, ..) if key == name -> Ok(value)
      _ -> Error(Nil)
    }
  })
}
