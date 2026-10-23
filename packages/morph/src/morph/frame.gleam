import gleam/list

/// A projection drawn as plain data. `morph/lustre/view` draws it on the web.
pub type Node {
  Text(String)
  Span(List(Attribute), List(Node))
  /// A line, or a block of lines.
  Div(List(Attribute), List(Node))
}

pub type Attribute {
  /// The highlighting token, i.e. "token keyword".
  Class(String)
  /// The path of the expression this node draws.
  Path(List(Int))
  Title(String)
  Indent
  Focus
  /// The expression has an error.
  Problem
}

// component, block panel
// enclosed bare clad
// prepend spans doesnt work on bare item
pub type Frame {
  Multiline(List(Node), List(Node), List(Node))
  Inline(List(Node))
  Statements(List(Node))
}

fn is_inline(m) {
  case m {
    Inline(spans) -> Ok(spans)
    _ -> Error(Nil)
  }
}

pub fn line_height(frame) {
  case frame {
    Inline(_) -> 1
    Multiline(_, inner, _) -> list.length(inner)
    Statements(inner) -> list.length(inner)
  }
}

pub fn all_inline(ms) {
  list.try_map(ms, is_inline)
}

pub fn prepend_spans(new, m) {
  case m {
    Inline(spans) -> Inline(list.append(new, spans))
    Multiline(pre, inner, post) -> Multiline(list.append(new, pre), inner, post)
    Statements(inner) ->
      prepend_spans(new, Multiline([Text("{")], inner, [Text("}")]))
  }
}

pub fn append_spans(m, new) {
  case m {
    Inline(spans) -> Inline(list.append(spans, new))
    Multiline(pre, inner, post) -> Multiline(pre, inner, list.append(post, new))
    Statements(inner) ->
      append_spans(Multiline([Text("{")], inner, [Text("}")]), new)
  }
}

pub fn join(a, b) {
  case a, b {
    Inline(spans), b -> prepend_spans(spans, b)
    a, Inline(spans) -> append_spans(a, spans)
    Multiline(pre, inner_a, span_a), Multiline(span_b, inner_b, post) -> {
      let middle = Div([], list.append(span_a, span_b))
      let inner = list.flatten([inner_a, [middle], inner_b])
      Multiline(pre, inner, post)
    }
    _, _ -> panic as "joining statements should not occur"
  }
}

pub fn delimit(frames, delimiter) {
  case list.reverse(frames) {
    [] -> []
    [last, ..rest] -> {
      let rest = list.map(rest, append_spans(_, [Text(delimiter)]))
      list.reverse([last, ..rest])
    }
  }
}

// Call to_divs but its a single div
// could return unwrapped divs but what about indent.
// have indent as an option
// wrap each line thing in it's own div
pub fn to_fat_line(exp) {
  case exp {
    Inline(spans) -> Div([], spans)
    Multiline([], inner, []) -> Div([], inner)
    Multiline(pre, inner, post) ->
      Div([], [Div([], pre), indent(inner), Div([], post)])
    Statements(inner) -> Div([], inner)
  }
}

fn indent(inner) {
  Div([Indent], inner)
}

pub fn to_fat_lines(lines) {
  list.map(lines, to_fat_line)
}
