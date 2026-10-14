import core/native as n
import core/native_view
import gleam/list
import gleam/result
import gleam_opentui as o
import signals/keyed
import signals/reactive as r
import terminal/app as a

pub fn mount(renderer, initial: a.Model, dispatch, directory) {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let screen = native_view.create(renderer, initial, dispatch, directory)
  let busy = r.signal(runtime, initial.busy)
  let chrome = r.signal(runtime, a.Model(..initial, entries: []))
  let empty = r.signal(runtime, True)
  r.within(runtime, owner, fn() {
    r.effect(runtime, fn() { screen.frame(r.read(chrome)) })
    r.effect(runtime, fn() { screen.empty(r.read(empty)) })
  })
  let rows =
    keyed.new(
      runtime,
      owner,
      fn(entry: a.Entry) { entry.id },
      fn(value) {
        let row = screen.create_row(r.untrack(runtime, fn() { r.read(value) }))
        r.effect(runtime, fn() {
          let entry = r.read(value)
          // Only assistant Markdown depends on global streaming state. Other rows
          // track their own entry, so a chunk doesn't revisit historical widgets.
          let streaming = case entry.role {
            a.Assistant -> r.read(busy)
            _ -> False
          }
          row.update(entry, streaming)
        })
        row
      },
      fn(row, index) {
        // The intro is a retained first child even while hidden.
        let already_there =
          o.children(screen.history)
          |> list.drop(index + 1)
          |> list.first
          |> result.map(fn(node) { o.node_id(node) == o.node_id(row.node) })
          |> result.unwrap(False)
        case already_there {
          True -> Nil
          False -> {
            o.add_at(screen.history, row.node, index + 1) |> n.must
            Nil
          }
        }
        Nil
      },
      fn(row) { o.destroy_node(row.node) |> n.must },
    )
  let update = fn(model: a.Model) {
    r.batch(runtime, fn() {
      r.write(chrome, a.Model(..model, entries: []))
      r.write(busy, model.busy)
      r.write(empty, list.is_empty(model.entries))
      keyed.update(rows, model.entries)
    })
  }
  update(initial)
  native_view.Mounted(screen, update, fn() {
    r.dispose(owner)
    screen.dispose()
  })
}
