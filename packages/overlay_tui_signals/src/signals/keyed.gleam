//// Keyed ownership for retained children. A surviving key keeps its signal,
//// native node and computation scope when its value or list position changes.

import gleam/dict
import gleam/list
import gleam/result
import signals/reactive as r
import terminal/cell

pub opaque type Keyed(key, item, node) {
  Keyed(update: fn(List(item)) -> Nil, get: fn(key) -> Result(node, Nil))
}

type Owned(item, node) {
  Owned(signal: r.Signal(item), node: node, owner: r.Scope)
}

pub fn new(
  runtime: r.Runtime,
  owner: r.Scope,
  key: fn(item) -> key,
  create: fn(r.Signal(item)) -> node,
  move: fn(node, Int) -> Nil,
  destroy: fn(node) -> Nil,
) -> Keyed(key, item, node) {
  let rows: cell.Cell(dict.Dict(key, Owned(item, node))) = cell.new(dict.new())
  let order = cell.new([])
  Keyed(
    fn(items) {
      r.batch(runtime, fn() {
        let keys = list.map(items, key)
        let desired = dict.from_list(list.map(keys, fn(id) { #(id, Nil) }))
        let assert True = dict.size(desired) == list.length(keys)
        cell.read(rows)
        |> dict.to_list
        |> list.each(fn(pair) {
          case dict.has_key(desired, pair.0) {
            True -> Nil
            False -> {
              r.dispose(pair.1.owner)
              cell.write(rows, dict.delete(cell.read(rows), pair.0))
            }
          }
        })
        let reordered = cell.read(order) != keys
        list.index_fold(items, Nil, fn(_, item, index) {
          let id = key(item)
          let row = case dict.get(cell.read(rows), id) {
            Ok(row) -> {
              r.write(row.signal, item)
              row
            }
            Error(_) -> {
              let scope = r.within(runtime, owner, fn() { r.scope(runtime) })
              let signal = r.signal(runtime, item)
              let node = r.within(runtime, scope, fn() { create(signal) })
              r.on_cleanup(scope, fn() { destroy(node) })
              let row = Owned(signal, node, scope)
              cell.write(rows, dict.insert(cell.read(rows), id, row))
              row
            }
          }
          case reordered {
            True -> move(row.node, index)
            False -> Nil
          }
        })
        cell.write(order, keys)
      })
    },
    fn(id) { dict.get(cell.read(rows), id) |> result.map(fn(row) { row.node }) },
  )
}

pub fn update(keyed: Keyed(key, item, node), items: List(item)) {
  keyed.update(items)
}

pub fn get(keyed: Keyed(key, item, node), id: key) {
  keyed.get(id)
}
