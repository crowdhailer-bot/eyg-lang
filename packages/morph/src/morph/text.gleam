//// Print `Editable` code using the syntax of `eyg_parser`.
//// Vacant nodes, which have no syntax, print as `?`.
//// Any node can be marked by its path, for example to show the focus of a projection.

import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import morph/editable as e
import morph/projection as p
import multiformats/cid/v1

/// Text placed around a marked node.
pub type Mark {
  Mark(open: String, close: String)
}

/// Lines longer than this are broken over several lines.
const width = 80

pub fn print(source: e.Expression) -> String {
  marked(source, [])
}

/// Print with the nodes at each path, as given by `projection.path`, wrapped in marks.
pub fn marked(source: e.Expression, marks: List(#(List(Int), Mark))) -> String {
  let marks =
    list.map(marks, fn(mark) {
      let #(path, mark) = mark
      #(list.reverse(path), mark)
    })
    |> dict.from_list
  top(source, [], 0, marks)
}

/// Print the whole program with the focus of the projection wrapped in the mark.
pub fn projection(projection: p.Projection, mark: Mark) -> String {
  marked(p.rebuild(projection), [#(p.path(projection), mark)])
}

type Marks =
  Dict(List(Int), Mark)

fn mark(text, rev, marks: Marks) {
  case dict.get(marks, rev) {
    Ok(Mark(open:, close:)) -> open <> text <> close
    Error(Nil) -> text
  }
}

fn pad(indent) {
  string.repeat(" ", indent)
}

fn newline(indent) {
  "\n" <> pad(indent)
}

fn is_inline(text) {
  !string.contains(text, "\n")
}

// A block at the top level, or as a function body, needs no wrapping.
fn top(exp, rev, indent, marks) {
  case exp {
    e.Block(assigns, then, _) ->
      block(assigns, then, rev, indent, marks) |> mark(rev, marks)
    _ -> expression(exp, rev, indent, marks)
  }
}

fn block(assigns, then, rev, indent, marks) {
  let statements =
    list.index_map(assigns, fn(assign, i) {
      let #(pattern, value) = assign
      statement(pattern, value, [i, ..rev], indent, marks)
    })
  let then = expression(then, [list.length(assigns), ..rev], indent, marks)
  string.join(list.append(statements, [then]), newline(indent))
}

fn statement(pattern, value, rev, indent, marks) {
  let pattern = print_pattern(pattern, [0, ..rev], marks)
  let value_rev = [1, ..rev]
  let assignment = case value {
    e.Block(..) ->
      "let "
      <> pattern
      <> " ="
      <> newline(indent + 2)
      <> expression(value, value_rev, indent + 2, marks)
    _ ->
      "let " <> pattern <> " = " <> expression(value, value_rev, indent, marks)
  }
  mark(assignment, rev, marks)
}

fn print_pattern(pattern, rev, marks) {
  case pattern {
    // The parser binds `$` for destructuring, with no fields it was `{}`.
    e.Bind("$") -> "{}"
    e.Bind(var) -> var
    e.Destructure(fields) -> {
      let fields =
        list.index_map(fields, fn(field, i) {
          let #(label, var) = field
          let label_rev = [i * 2, ..rev]
          let var_rev = [i * 2 + 1, ..rev]
          case label == var && !has_mark(label_rev, marks) {
            True -> mark(var, var_rev, marks)
            False ->
              mark(label, label_rev, marks) <> ": " <> mark(var, var_rev, marks)
          }
        })
      "{" <> string.join(fields, ", ") <> "}"
    }
  }
  |> mark(rev, marks)
}

fn has_mark(rev, marks) {
  dict.has_key(marks, rev)
}

fn expression(exp, rev, indent, marks) -> String {
  case exp {
    e.Block(assigns, then, _) -> block(assigns, then, rev, indent, marks)
    e.Function([e.Bind("$")], e.Case(e.Variable("$"), matches, otherwise)) ->
      case_(None, matches, otherwise, [1, ..rev], indent, marks)
    e.Function(params, body) -> function(params, body, rev, indent, marks)
    e.Call(func, args) -> {
      let func = expression(func, [0, ..rev], indent, marks)
      let args = list.index_map(args, fn(arg, i) { #(arg, [i + 1, ..rev]) })
      sequence(func <> "(", args, None, ")", indent, marks)
    }
    e.Vacant -> "?"
    e.Variable(var) -> var
    e.Integer(value) -> int.to_string(value)
    e.Binary(value) -> binary(value)
    e.String(value) -> "\"" <> escape(value) <> "\""
    e.List(items, tail) -> {
      let items = list.index_map(items, fn(item, i) { #(item, [i, ..rev]) })
      let tail =
        option.map(tail, fn(tail) { #(tail, [list.length(items), ..rev]) })
      sequence("[", items, tail, "]", indent, marks)
    }
    e.Record(fields, original) -> record(fields, original, rev, indent, marks)
    e.Select(from, label) ->
      expression(from, [0, ..rev], indent, marks)
      <> "."
      <> mark(label, [1, ..rev], marks)
    e.Tag(label) -> label
    e.Case(top, matches, otherwise) ->
      case_(Some(top), matches, otherwise, rev, indent, marks)
    e.Perform(label) -> "perform " <> label
    e.Deep(label) -> "handle " <> label
    e.Builtin(identifier) -> "!" <> identifier
    e.Reference(reference) -> reference_to_string(reference)
  }
  |> mark(rev, marks)
}

fn function(params, body, rev, indent, marks) {
  let params =
    list.index_map(params, fn(param, i) {
      print_pattern(param, [i, ..rev], marks)
    })
  let head = "(" <> string.join(params, ", ") <> ") -> {"
  let body_rev = [list.length(params), ..rev]
  let inline = case body {
    e.Block(..) -> Error(Nil)
    _ -> {
      let text = expression(body, body_rev, indent + 2, marks)
      case is_inline(text) && fits(indent, [head, text]) {
        True -> Ok(head <> " " <> text <> " }")
        False -> Error(Nil)
      }
    }
  }
  case inline {
    Ok(text) -> text
    Error(Nil) ->
      head
      <> newline(indent + 2)
      <> top(body, body_rev, indent + 2, marks)
      <> newline(indent)
      <> "}"
  }
}

fn fits(indent, parts) {
  let line = case string.split(string.concat(parts), "\n") |> list.last {
    Ok(line) -> line
    Error(Nil) -> ""
  }
  indent + string.length(line) <= width
}

// Arguments, list items and their spread tail.
// A final multiline item is allowed to open on the same line, as in `f(x, (y) -> {`.
fn sequence(open, items, tail, close, indent, marks) {
  let inner =
    list.map(items, fn(item) {
      let #(exp, rev) = item
      expression(exp, rev, indent + 2, marks)
    })
  let inner = case tail {
    Some(#(exp, rev)) ->
      list.append(inner, [".." <> expression(exp, rev, indent + 2, marks)])
    None -> inner
  }
  case list.all(inner, is_inline) && fits(indent, [open, ..inner]) {
    True -> open <> string.join(inner, ", ") <> close
    False -> {
      let hug = case list.reverse(items), tail {
        [#(e.Function(..) as last, rev), ..before], None -> {
          let before = list.take(inner, list.length(before))
          let last = expression(last, rev, indent, marks)
          case list.all(before, is_inline) && fits(indent, [open, ..before]) {
            True if before == [] -> Ok(open <> last <> close)
            True ->
              Ok(open <> string.join(before, ", ") <> ", " <> last <> close)
            False -> Error(Nil)
          }
        }
        _, _ -> Error(Nil)
      }
      case hug {
        Ok(text) -> text
        Error(Nil) ->
          open
          <> newline(indent + 2)
          <> string.join(inner, "," <> newline(indent + 2))
          <> newline(indent)
          <> close
      }
    }
  }
}

fn record(fields, original, rev, indent, marks) {
  let inner =
    list.index_map(fields, fn(field, i) {
      let #(label, value) = field
      let label_rev = [i * 2, ..rev]
      let value_rev = [i * 2 + 1, ..rev]
      let marked = has_mark(label_rev, marks) || has_mark(value_rev, marks)
      case value, marked {
        e.Variable(var), False if var == label -> label
        _, _ ->
          mark(label, label_rev, marks)
          <> ": "
          <> expression(value, value_rev, indent + 2, marks)
      }
    })
  let inner = case original {
    Some(original) -> {
      let original_rev = [list.length(fields) * 2, ..rev]
      list.append(inner, [
        ".." <> expression(original, original_rev, indent + 2, marks),
      ])
    }
    None -> inner
  }
  case list.all(inner, is_inline) && fits(indent, ["{", ..inner]) {
    True -> "{" <> string.join(inner, ", ") <> "}"
    False ->
      "{"
      <> newline(indent + 2)
      <> string.join(inner, "," <> newline(indent + 2))
      <> newline(indent)
      <> "}"
  }
}

fn case_(top, matches, otherwise, rev, indent, marks) {
  let head = case top {
    Some(top) -> "match " <> expression(top, [0, ..rev], indent, marks) <> " {"
    None -> "match {"
  }
  let branches =
    list.index_map(matches, fn(match, i) {
      let #(label, branch) = match
      let label_rev = [i + 1, ..rev]
      let branch_rev = [0, ..label_rev]
      let branch = case branch {
        e.Function(..) -> expression(branch, branch_rev, indent + 2, marks)
        _ -> " " <> expression(branch, branch_rev, indent + 2, marks)
      }
      mark(label, label_rev, marks) <> branch
    })
  let otherwise = case otherwise {
    Some(otherwise) -> {
      let otherwise_rev = [list.length(matches) + 1, ..rev]
      ["| " <> expression(otherwise, otherwise_rev, indent + 2, marks)]
    }
    None -> []
  }
  head
  <> newline(indent + 2)
  <> string.join(list.append(branches, otherwise), newline(indent + 2))
  <> newline(indent)
  <> "}"
}

fn escape(value) {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
  |> string.replace("\r", "\\r")
}

// Binaries have no literal syntax, print the builtin call that builds the same value.
fn binary(value) {
  let bytes = bytes(value, [])
  "!binary_from_integers([" <> string.join(bytes, ", ") <> "])"
}

fn bytes(value, acc) {
  case value {
    <<byte, rest:bytes>> -> bytes(rest, [int.to_string(byte), ..acc])
    _ -> list.reverse(acc)
  }
}

fn reference_to_string(reference) {
  case reference {
    ir.Content(cid) -> "#" <> v1.to_string(cid)
    ir.Relative(path) -> "import \"" <> escape(path) <> "\""
    ir.Package(package) -> "@" <> package
    ir.Version(package, version) ->
      "@" <> package <> ":" <> int.to_string(version)
    ir.Pinned(ir.Release(package, version, module)) ->
      "@"
      <> package
      <> ":"
      <> int.to_string(version)
      <> ":"
      <> v1.to_string(module)
  }
}
