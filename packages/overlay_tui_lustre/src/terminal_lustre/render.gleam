//// Headless render loop over Lustre's real VDOM, diff, memo and event cache.
//// The shared terminal controller owns Model-Update and application commands.
//// This module adds no alternative diff algorithm or JavaScript runtime.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/result
import lustre/runtime/transport
import lustre/vdom/cache
import lustre/vdom/diff
import terminal/cell

pub opaque type Render(model, message) {
  Render(update: fn(model) -> Nil, event: fn(String, String, Dynamic) -> Nil)
}

pub fn start(initial, view, receive, dispatch) {
  let node = view(initial)
  let state = cell.new(#(node, cache.from_node(node)))
  receive(transport.mount(
    False,
    False,
    [],
    [],
    [],
    dict.new(),
    node,
    cache.memos(cell.read(state).1),
  ))
  Render(
    fn(model) {
      let #(before, cached) = cell.read(state)
      let next = view(model)
      let changes = diff.diff(cached, before, next)
      cell.write(state, #(next, changes.cache))
      receive(transport.reconcile(changes.patch, cache.memos(changes.cache)))
    },
    fn(path, name, data) {
      let #(node, cached) = cell.read(state)
      let #(cached, handled) = cache.handle(cached, path, name, data)
      cell.write(state, #(node, cached))
      let _ = result.map(handled, fn(event) { dispatch(event.message) })
      Nil
    },
  )
}

pub fn update(render: Render(model, message), model: model) {
  render.update(model)
}

pub fn event(render: Render(model, message), path, name, data) {
  render.event(path, name, data)
}
