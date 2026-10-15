//// Offline presentation behavior. HTML and CSS remain in the blog template.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import javascript/mutable_reference as reference
import plinthx/browser/node as dom
import plinthx/javascript/foreign

fn data(value) {
  foreign.to_dynamic(value)
}

fn call(target, name, args) {
  foreign.call(target, name, array.from_list(args))
}

fn text(value) {
  decode.run(value, decode.string) |> result.unwrap("")
}

fn element(id) {
  let assert Ok(node) = dom.by_id(id)
  node
}

fn query(root, selector) {
  let assert Ok(nodes) = dom.query(root, selector)
  nodes
}

fn classes(node) {
  foreign.property(data(node), "classList")
}

fn toggle(node, name, enabled) {
  let _ = call(classes(node), "toggle", [data(name), data(enabled)])
  Nil
}

fn window() {
  foreign.property(data(dom.document()), "defaultView")
}

pub fn clamp(index, count) {
  int.max(0, int.min(count - 1, index))
}

/// Illustrative independent attempts, rather than the finite-sample estimators.
pub fn probabilities(percent, attempts) {
  let p = int.to_float(int.max(0, int.min(100, percent))) /. 100.0
  let k = int.max(1, attempts)
  let power = fn(base) {
    int.range(0, k, with: 1.0, run: fn(acc, _) { acc *. base })
  }
  #(p, 1.0 -. power(1.0 -. p), power(p))
}

fn fit() {
  let viewport = element("viewport")
  let scale =
    float.min(
      { dom.number(viewport, "clientWidth") -. 24.0 } /. 1280.0,
      { dom.number(viewport, "clientHeight") -. 24.0 } /. 720.0,
    )
  dom.style(
    element("stage"),
    "transform",
    "scale(" <> float.to_string(float.max(0.05, scale)) <> ")",
  )
}

fn illustration() {
  let p =
    dom.text(element("probability"), "value") |> int.parse |> result.unwrap(80)
  let k =
    dom.text(element("attempts"), "value") |> int.parse |> result.unwrap(5)
  let #(one, any, all) = probabilities(p, k)
  dom.set_text(element("p-label"), "value", int.to_string(p) <> "%")
  dom.set_text(element("k-label"), "value", int.to_string(k))
  list.each([#("one", one), #("any", any), #("all", all)], fn(pair) {
    dom.style(
      element("bar-" <> pair.0),
      "width",
      float.to_string(pair.1 *. 100.0) <> "%",
    )
    dom.set_text(
      element(pair.0 <> "-result"),
      "value",
      float.to_string(int.to_float(float.round(pair.1 *. 1000.0)) /. 10.0)
        <> "%",
    )
  })
}

fn notes() {
  let shown =
    call(classes(dom.body()), "contains", [data("show-notes")]) == data(True)
  toggle(dom.body(), "show-notes", !shown)
  dom.set_attribute(element("notes-button"), "aria-pressed", case shown {
    True -> "false"
    False -> "true"
  })
  fit()
}

fn fullscreen() {
  let active =
    decode.run(
      foreign.property(data(dom.document()), "fullscreenElement"),
      decode.optional(decode.dynamic),
    )
  let work = case active {
    Ok(Some(_)) -> call(data(dom.document()), "exitFullscreen", [])
    _ -> call(data(dom.root()), "requestFullscreen", [])
  }
  let _ =
    foreign.to_promise(work)
    |> promise.map(fn(_) { Nil })
    |> promise.rescue(fn(_) { Nil })
  Nil
}

fn print() {
  let _ = call(window(), "print", [])
  Nil
}

fn on(id, event, handle) {
  dom.listen(element(id), event, fn(_) { handle() })
}

pub fn main() {
  let slides = query(dom.document(), ".slide")
  let count = list.length(slides)
  assert count > 0
  let current = reference.new(0)
  let jump = element("jump")
  list.index_map(slides, fn(slide, index) {
    let title = dom.attribute(slide, "data-title") |> result.unwrap("")
    dom.set_attribute(
      slide,
      "data-page",
      int.to_string(index + 1) <> " / " <> int.to_string(count),
    )
    dom.set_attribute(
      slide,
      "aria-label",
      int.to_string(index + 1) <> ". " <> title,
    )
    let option = dom.create("option")
    dom.set_text(option, "value", int.to_string(index))
    dom.set_text(
      option,
      "textContent",
      int.to_string(index + 1) <> " · " <> title,
    )
    dom.append(jump, option)
  })
  let show = fn(index, update_hash) {
    let index = clamp(index, count)
    let _ = reference.set(current, index)
    list.index_map(slides, fn(slide, position) {
      toggle(slide, "active", position == index)
      dom.set_attribute(slide, "aria-hidden", case position == index {
        True -> "false"
        False -> "true"
      })
    })
    let assert Ok(slide) = list.first(list.drop(slides, index))
    let title = dom.attribute(slide, "data-title") |> result.unwrap("")
    dom.set_text(jump, "value", int.to_string(index))
    dom.set_text(
      element("counter"),
      "textContent",
      int.to_string(index + 1) <> " / " <> int.to_string(count),
    )
    dom.set_flag(element("previous"), "disabled", index == 0)
    dom.set_flag(element("next"), "disabled", index == count - 1)
    dom.style(
      element("progress"),
      "width",
      float.to_string(int.to_float(index + 1) /. int.to_float(count) *. 100.0)
        <> "%",
    )
    let panel = element("notes-panel")
    dom.set_text(panel, "innerHTML", "")
    let heading = dom.create("h3")
    dom.set_text(
      heading,
      "textContent",
      int.to_string(index + 1) <> ". " <> title,
    )
    dom.append(panel, heading)
    case query(slide, ".notes") {
      [notes, ..] -> {
        let _ =
          call(data(panel), "insertAdjacentHTML", [
            data("beforeend"),
            data(dom.text(notes, "innerHTML")),
          ])
        Nil
      }
      [] -> Nil
    }
    dom.set_number(panel, "scrollTop", 0.0)
    case update_hash {
      True -> {
        let _ =
          call(foreign.property(window(), "history"), "replaceState", [
            foreign.null_value(),
            data(""),
            data("#" <> { dom.attribute(slide, "id") |> result.unwrap("") }),
          ])
        Nil
      }
      False -> Nil
    }
    dom.set_text(
      dom.document(),
      "title",
      int.to_string(index + 1) <> ". " <> title <> " — Overlay evals",
    )
  }
  let from_hash = fn() {
    let hash =
      foreign.property(foreign.property(window(), "location"), "hash") |> text
    let index =
      list.index_map(slides, fn(slide, index) {
        #(dom.attribute(slide, "id") |> result.unwrap(""), index)
      })
      |> list.key_find(string.drop_start(hash, 1))
      |> result.unwrap(0)
    show(index, False)
  }
  list.each(query(dom.document(), "a[data-code]"), fn(link) {
    let path = dom.attribute(link, "data-code") |> result.unwrap("")
    let last = string.split(path, "/") |> list.last |> result.unwrap("")
    let kind = case string.contains(last, ".") {
      True -> "blob"
      False -> "tree"
    }
    dom.set_attribute(
      link,
      "href",
      "https://github.com/crowdhailer-bot/eyg-lang/"
        <> kind
        <> "/810edee4/"
        <> path,
    )
    dom.set_attribute(link, "target", "_blank")
    dom.set_attribute(link, "rel", "noopener noreferrer")
  })
  on("previous", "click", fn() { show(reference.get(current) - 1, True) })
  on("next", "click", fn() { show(reference.get(current) + 1, True) })
  on("jump", "change", fn() {
    show(dom.text(jump, "value") |> int.parse |> result.unwrap(0), True)
  })
  on("notes-button", "click", notes)
  on("fullscreen-button", "click", fullscreen)
  on("print-button", "click", print)
  on("probability", "input", illustration)
  on("attempts", "input", illustration)
  dom.listen_global("resize", fn(_) { fit() })
  dom.listen_global("hashchange", fn(_) { from_hash() })
  dom.listen(dom.document(), "keydown", fn(event) {
    let target = dom.target(event)
    let key = dom.key(event) |> string.lowercase
    let interactive =
      call(data(target), "matches", [data("input,select,textarea")])
      == data(True)
    let on_button =
      call(data(target), "closest", [data("button,a")])
      |> decode.run(decode.optional(decode.dynamic))
    let on_button = case on_button {
      Ok(Some(_)) -> True
      _ -> False
    }
    case
      interactive
      || dom.modifier(event, "ctrlKey")
      || dom.modifier(event, "metaKey")
      || dom.modifier(event, "altKey")
      || { on_button && list.contains([" ", "enter"], key) }
    {
      True -> Nil
      False -> {
        case
          list.contains(
            [
              "arrowright",
              "pagedown",
              " ",
              "arrowleft",
              "pageup",
              "home",
              "end",
              "n",
              "f",
              "p",
            ],
            key,
          )
        {
          True -> dom.prevent_default(event)
          False -> Nil
        }
        case key {
          "arrowright" | "pagedown" | " " ->
            show(reference.get(current) + 1, True)
          "arrowleft" | "pageup" -> show(reference.get(current) - 1, True)
          "home" -> show(0, True)
          "end" -> show(count - 1, True)
          "n" -> notes()
          "f" -> fullscreen()
          "p" -> print()
          _ -> Nil
        }
      }
    }
  })
  dom.listen_global("beforeprint", fn(_) {
    list.each(slides, fn(slide) { dom.remove_attribute(slide, "aria-hidden") })
  })
  dom.listen_global("afterprint", fn(_) { show(reference.get(current), False) })
  illustration()
  from_hash()
  fit()
}
