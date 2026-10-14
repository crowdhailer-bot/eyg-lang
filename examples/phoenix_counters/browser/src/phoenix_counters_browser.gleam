import gleam/javascript/promise
import gleam/list
import gleam/result
import javascript/mutable_reference as cell
import phoenix
import phoenix_counters_browser/grammar
import phoenix_counters_browser/theme
import plinthx/browser/node as n
import shiki

pub fn main() {
  theme.start()
  let csrf =
    first(n.document(), "meta[name='csrf-token']")
    |> n.attribute("content")
    |> result.unwrap("")
  let highlighter = shiki.create(grammar.data)
  let hook = phoenix.hook(fn(hook) { mounted(hook, highlighter) })
  let socket = phoenix.new_socket("/live", csrf, 2500, [#("ScriptBox", hook)])
  phoenix.connect(socket)
}

fn first(root, selector) {
  let assert Ok(nodes) = n.query(root, selector)
  let assert [node, ..] = nodes
  node
}

fn mounted(hook, highlighter) {
  let element = phoenix.element(hook)
  let input = first(element, "textarea")
  let output = first(element, "pre")
  let alive = cell.new(True)
  let revision = cell.new(0)
  let highlight = fn() {
    let source = n.value(input) |> result.unwrap("")
    let expected = cell.get(revision) + 1
    let _ = cell.set(revision, expected)
    let _ =
      promise.map(highlighter, fn(highlighter) {
        case cell.get(alive) && cell.get(revision) == expected, highlighter {
          True, Ok(highlighter) -> {
            case shiki.highlight(highlighter, source, "eyg", "github-dark") {
              Ok(tokens) -> render(output, tokens)
              Error(_) -> n.set_text(output, "textContent", source <> "\n ")
            }
          }
          _, _ -> Nil
        }
      })
    Nil
  }
  let changed = fn(_) { highlight() }
  let scrolled = fn(_) {
    n.set_number(output, "scrollTop", n.number(input, "scrollTop"))
    n.set_number(output, "scrollLeft", n.number(input, "scrollLeft"))
  }
  let pressed = fn(event) {
    case n.key(event) == "Enter" && !n.modifier(event, "shiftKey") {
      True -> {
        n.prevent_default(event)
        case n.form(input) {
          Ok(form) -> n.submit(form)
          Error(_) -> Nil
        }
      }
      False -> Nil
    }
  }
  n.listen(input, "input", changed)
  n.listen(input, "scroll", scrolled)
  n.listen(input, "keydown", pressed)
  phoenix.handle_event(hook, "clear", fn(_) {
    n.set_text(input, "value", "")
    let _ = n.event(input, "input")
    Nil
  })
  highlight()
  fn() {
    let _ = cell.set(alive, False)
    n.unlisten(input, "input", changed)
    n.unlisten(input, "scroll", scrolled)
    n.unlisten(input, "keydown", pressed)
  }
}

fn render(output, highlighted: shiki.Highlight) {
  n.set_text(output, "textContent", "")
  highlighted.lines
  |> list.index_map(fn(line, index) {
    case index {
      0 -> Nil
      _ -> append(output, "\n", highlighted.foreground)
    }
    list.each(line, fn(token) { append(output, token.content, token.color) })
  })
  let _ = append(output, "\n ", highlighted.foreground)
  Nil
}

fn append(output, text, color) {
  let span = n.create("span")
  n.set_text(span, "textContent", text)
  n.style(span, "color", color)
  n.append(output, span)
}
