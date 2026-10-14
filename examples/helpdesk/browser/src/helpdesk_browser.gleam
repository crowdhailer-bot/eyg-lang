import gleam/float
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import helpdesk_browser/grammar
import javascript/mutable_reference as cell
import plinthx/browser/node as n
import shiki

const source = "textarea[name$=\"[source]\"]"

const result = ".max-w-2xl.mx-auto.mt-6 > div"

const error = "textarea[name$=\"[source]\"] ~ p.text-rose-600"

const styles =
  "textarea[name$='[source]'], .max-w-2xl.mx-auto.mt-6 > div, .eyg-overlay { font-family: ui-monospace, monospace !important; font-size: 0.9rem !important; line-height: 1.5 !important; white-space: pre-wrap; overflow-wrap: anywhere; } textarea[name$='[source]'] { min-height: 14rem; color: transparent !important; caret-color: #e1e4e8; background: #24292e !important; } .max-w-2xl.mx-auto.mt-6 > div { background: #24292e !important; color: #e1e4e8; } .eyg-overlay { position: fixed; margin: 0; overflow: hidden; pointer-events: none; box-sizing: border-box; border-style: solid; border-color: transparent; z-index: 10; } form:has(textarea[name$='[source]']) > div.mb-4.text-rose-600 { display: none; } textarea[name$='[source]'] ~ p.text-rose-600 { display: block; white-space: pre-wrap; font-family: ui-monospace, monospace; }"

pub fn main() {
  let style = n.create("style")
  n.set_text(style, "textContent", styles)
  case query("head") {
    [head] -> n.append(head, style)
    _ -> Nil
  }
  let overlay = cell.new(None)
  use highlighter <- promise.map(shiki.create(grammar.data))
  let assert Ok(highlighter) = highlighter
  loop(highlighter, overlay)
}

fn loop(highlighter, overlay) {
  let _ =
    promise.map(n.frame(), fn(_) {
      frame(highlighter, overlay)
      loop(highlighter, overlay)
    })
  Nil
}

fn query(selector) {
  n.query(n.document(), selector) |> result.unwrap([])
}

fn frame(highlighter, overlay) {
  case query(source) {
    [] -> {
      case cell.get(overlay) {
        Some(node) -> n.remove(node)
        None -> Nil
      }
      let _ = cell.set(overlay, None)
      Nil
    }
    [input, ..] -> {
      n.set_flag(input, "spellcheck", False)
      let output = case cell.get(overlay) {
        Some(node) -> node
        None -> {
          let node = n.create("pre")
          n.set_text(node, "className", "eyg-overlay")
          n.append(n.body(), node)
          let _ = cell.set(overlay, Some(node))
          node
        }
      }
      let #(left, top, width, height) = n.rect(input)
      list.each(
        [#("left", left), #("top", top), #("width", width), #("height", height)],
        fn(item) { n.style(output, item.0, float.to_string(item.1) <> "px") },
      )
      list.each(["padding", "borderWidth"], fn(property) {
        n.style(output, property, n.computed_style(input, property))
      })
      let text = n.value(input) |> result.unwrap("")
      case n.attribute(output, "data-source") != Ok(text) {
        True -> {
          n.set_attribute(output, "data-source", text)
          highlight(output, highlighter, text <> "\n ")
        }
        False -> Nil
      }
      n.set_number(output, "scrollTop", n.number(input, "scrollTop"))
      list.each(query(error), fn(node) {
        let text = n.text(node, "textContent")
        let trimmed = string.trim(text)
        case text != trimmed {
          True -> n.set_text(node, "textContent", trimmed)
          False -> Nil
        }
      })
      list.each(query(result), fn(node) {
        case n.query(node, ".eyg-token") {
          Ok([]) ->
            highlight(
              node,
              highlighter,
              string.trim(n.text(node, "textContent")),
            )
          _ -> Nil
        }
      })
    }
  }
}

fn highlight(output, highlighter, text) {
  case shiki.highlight(highlighter, text, "eyg", "github-dark") {
    Error(_) -> n.set_text(output, "textContent", text)
    Ok(highlighted) -> {
      n.set_text(output, "textContent", "")
      highlighted.lines
      |> list.index_map(fn(line, index) {
        case index {
          0 -> Nil
          _ -> append(output, "\n", highlighted.foreground)
        }
        list.each(line, fn(token) { append(output, token.content, token.color) })
      })
      Nil
    }
  }
}

fn append(output, text, color) {
  let span = n.create("span")
  n.set_text(span, "className", "eyg-token")
  n.set_text(span, "textContent", text)
  n.style(span, "color", color)
  n.append(output, span)
}
