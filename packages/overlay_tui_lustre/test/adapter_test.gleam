import core/native as n
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam_opentui as o
import gleam_opentui/testing as t
import gleeunit/should
import lustre/element as e
import lustre/element/keyed
import lustre/event
import terminal/cell
import terminal_lustre/adapter
import terminal_lustre/render
import terminal_lustre/view as v

pub fn actual_lustre_keyed_patches_keep_native_identity_and_dispose_removed_nodes_test() {
  use setup <- promise.await(t.create("{\"width\":40,\"height\":12}"))
  let setup = setup |> should.be_ok
  let style = n.style()
  let built = cell.new(0)
  let adapter = adapter.new(t.renderer(setup), style, fn(_, _, _) { Nil })
  let first = #("a", "one")
  let second = #("b", "two")
  let view = fn(items: List(#(String, String))) {
    keyed.element(
      "box",
      [v.options([n.s("flexDirection", "column")])],
      list.map(items, fn(item) {
        #(
          item.0,
          e.memo([e.ref(item)], fn() {
            cell.write(built, cell.read(built) + 1)
            v.text(item.1, "#ffffff", [n.s("id", "item-" <> item.0)], [])
          }),
        )
      }),
    )
  }
  let renderer =
    render.start([first, second], view, adapter.receive(adapter, _), fn(_) {
      Nil
    })
  let first_node =
    adapter.find(adapter, "item-a") |> should.be_ok |> adapter.node
  let second_node =
    adapter.find(adapter, "item-b") |> should.be_ok |> adapter.node
  render.update(renderer, [#("b", "two updated"), first, #("c", "three")])
  adapter.find(adapter, "item-a")
  |> should.be_ok
  |> adapter.node
  |> should.equal(first_node)
  adapter.find(adapter, "item-b")
  |> should.be_ok
  |> adapter.node
  |> should.equal(second_node)
  let reused_count = cell.read(built)
  use _ <- promise.await(t.render_once(setup))
  let moved = t.capture(setup)
  render.update(renderer, [first])
  let removed = o.is_destroyed(second_node)
  use _ <- promise.map(t.render_once(setup))
  let final_frame = t.capture(setup)
  adapter.dispose(adapter)
  o.destroy_style(style) |> should.be_ok
  o.destroy_renderer(t.renderer(setup)) |> should.be_ok
  reused_count |> should.equal(4)
  removed |> should.be_true
  moved |> string.starts_with("two updated") |> should.be_true
  final_frame |> string.contains("one") |> should.be_true
  final_frame |> string.contains("two") |> should.be_false
}

pub fn fragment_and_mapped_event_paths_follow_keyed_moves_test() {
  use setup <- promise.await(t.create(
    "{\"width\":40,\"height\":12,\"useMouse\":true}",
  ))
  let setup = setup |> should.be_ok
  let style = n.style()
  let messages = cell.new([])
  let current = cell.new(None)
  let adapter =
    adapter.new(t.renderer(setup), style, fn(path, name, data) {
      let assert Some(rendered) = cell.read(current)
      render.event(rendered, path, name, data)
    })
  let view = fn(items: List(#(String, String))) {
    e.fragment([
      keyed.element(
        "box",
        [v.options([n.s("flexDirection", "column")])],
        list.map(items, fn(item) {
          #(
            item.0,
            e.map(
              e.fragment([
                v.text(item.1, "#ffffff", [n.s("id", item.0)], [
                  event.on("mousedown", decode.success(item.1)),
                ]),
              ]),
              fn(text) { "selected: " <> text },
            ),
          )
        }),
      ),
      v.text("footer", "#ffffff", [], []),
    ])
  }
  let rendered =
    render.start(
      [#("a", "one"), #("b", "two")],
      view,
      adapter.receive(adapter, _),
      fn(message) { cell.write(messages, [message, ..cell.read(messages)]) },
    )
  cell.write(current, Some(rendered))
  render.update(rendered, [#("b", "new two"), #("a", "one")])
  use _ <- promise.await(t.render_once(setup))
  let second = adapter.find(adapter, "b") |> should.be_ok |> adapter.node
  use clicked <- promise.map(t.click(t.mouse(setup), o.x(second), o.y(second)))
  should.be_ok(clicked)
  adapter.dispose(adapter)
  o.destroy_style(style) |> should.be_ok
  o.destroy_renderer(t.renderer(setup)) |> should.be_ok
  cell.read(messages) |> should.equal(["selected: new two"])
}
