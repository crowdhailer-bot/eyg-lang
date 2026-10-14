//// Small Gleam conveniences over the direct host bindings. These functions
//// own no state or reconciliation; all returned objects are OpenTUI nodes.

import gleam/float
import gleam/int
import gleam/json as j
import gleam/list
import gleam_opentui as o
import terminal/highlight as h

pub fn must(result: Result(a, String)) -> a {
  case result {
    Ok(value) -> value
    Error(message) -> panic as message
  }
}

pub fn props(properties) {
  j.object(properties) |> j.to_string
}

pub fn s(name, value) {
  #(name, j.string(value))
}

pub fn n(name, value) {
  #(name, j.int(value))
}

pub fn b(name, value) {
  #(name, j.bool(value))
}

pub fn box(renderer, parent, options) {
  let node =
    o.new_box(renderer, props([s("flexDirection", "column"), ..options]))
    |> must
  o.add(parent, node) |> must
  node
}

pub fn text(renderer, parent, value, color, options) {
  let node =
    o.new_text(
      renderer,
      props([s("content", value), s("fg", color), ..options]),
    )
    |> must
  o.add(parent, node) |> must
  node
}

pub fn scroll(renderer, parent, options) {
  let node =
    o.new_scroll_box(
      renderer,
      props([#("scrollbarOptions", j.object([b("visible", False)])), ..options]),
    )
    |> must
  o.add(parent, node) |> must
  node
}

pub fn clear(node) {
  list.each(o.children(node), fn(child) { o.destroy_node(child) |> must })
}

pub fn code(node, source) {
  h.tokens(source)
  |> list.map(fn(token) { o.Chunk(token.text, token.color, "", 0) })
  |> styled(node, _)
}

pub fn styled(node, chunks) {
  o.new_styled_text(chunks) |> must |> o.set_styled_content(node, _) |> must
}

pub fn style() {
  [
    #("comment", j.object([s("fg", h.muted), b("italic", True)])),
    #("string", j.object([s("fg", h.accent)])),
    #("reference", j.object([s("fg", h.blue)])),
    #("builtin", j.object([s("fg", h.blue)])),
    #("number", j.object([s("fg", h.orange)])),
    #("tag", j.object([s("fg", h.orange)])),
    #("keyword", j.object([s("fg", h.purple)])),
  ]
  |> props
  |> o.new_syntax_style
  |> must
}

pub fn milliseconds(value) {
  float.round(value) |> int.to_string
}

pub fn highlight(editor, style) {
  o.clear_highlights(editor) |> must
  list.each(h.tokens(o.plain_text(editor)), fn(token) {
    case o.style_id(style, token.kind) |> must {
      Ok(id) -> o.add_highlight(editor, token.start, token.end, id) |> must
      Error(_) -> Nil
    }
  })
}
