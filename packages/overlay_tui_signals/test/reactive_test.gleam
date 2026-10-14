import gleam/list
import gleeunit/should
import signals/keyed
import signals/reactive as r
import terminal/cell

pub fn diamond_dependencies_settle_before_an_effect_and_batch_once_test() {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let source = r.signal(runtime, 1)
  let seen = cell.new([])
  r.within(runtime, owner, fn() {
    let left = r.memo(runtime, fn() { r.read(source) * 2 })
    let right = r.memo(runtime, fn() { r.read(source) + 10 })
    let sum = r.memo(runtime, fn() { r.read_memo(left) + r.read_memo(right) })
    r.effect(runtime, fn() {
      cell.write(seen, [r.read_memo(sum), ..cell.read(seen)])
    })
  })
  r.batch(runtime, fn() {
    r.write(source, 2)
    r.write(source, 3)
  })
  cell.read(seen) |> should.equal([19, 13])
  r.write(source, 3)
  cell.read(seen) |> should.equal([19, 13])
  r.dispose(owner)
  r.write(source, 4)
  cell.read(seen) |> should.equal([19, 13])
}

pub fn dynamic_dependencies_unsubscribe_and_untrack_does_not_subscribe_test() {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let use_left = r.signal(runtime, True)
  let left = r.signal(runtime, 1)
  let right = r.signal(runtime, 10)
  let ignored = r.signal(runtime, 0)
  let seen = cell.new([])
  r.within(runtime, owner, fn() {
    r.effect(runtime, fn() {
      let _ = r.untrack(runtime, fn() { r.read(ignored) })
      let value = case r.read(use_left) {
        True -> r.read(left)
        False -> r.read(right)
      }
      cell.write(seen, [value, ..cell.read(seen)])
    })
  })
  r.write(ignored, 1)
  r.write(right, 11)
  r.write(use_left, False)
  r.write(left, 2)
  r.write(right, 12)
  cell.read(seen) |> should.equal([12, 11, 1])
  r.dispose(owner)
}

pub fn nested_computations_and_cleanup_follow_owner_lifetime_test() {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let outer = r.signal(runtime, 0)
  let inner = r.signal(runtime, 0)
  let events = cell.new([])
  let log = fn(text) { cell.write(events, [text, ..cell.read(events)]) }
  r.within(runtime, owner, fn() {
    r.effect(runtime, fn() {
      let _ = r.read(outer)
      log("outer")
      r.cleanup(runtime, fn() { log("outer cleanup") })
      r.effect(runtime, fn() {
        let _ = r.read(inner)
        log("inner")
        r.cleanup(runtime, fn() { log("inner cleanup") })
      })
      Nil
    })
  })
  r.write(outer, 1)
  r.write(inner, 1)
  r.dispose(owner)
  r.dispose(owner)
  let before = cell.read(events)
  r.write(inner, 2)
  cell.read(events) |> should.equal(before)
  list.reverse(before)
  |> should.equal([
    "outer", "inner", "inner cleanup", "outer cleanup", "outer", "inner",
    "inner cleanup", "inner", "inner cleanup", "outer cleanup",
  ])
}

pub fn disposing_a_queued_effect_prevents_its_callback_test() {
  let runtime = r.new()
  let source = r.signal(runtime, 1)
  let calls = cell.new(0)
  let stop =
    r.effect(runtime, fn() {
      let _ = r.read(source)
      cell.write(calls, cell.read(calls) + 1)
    })
  r.batch(runtime, fn() {
    r.write(source, 2)
    stop()
  })
  cell.read(calls) |> should.equal(1)
}

pub fn keyed_rows_keep_identity_across_moves_and_dispose_removed_rows_test() {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let created = cell.new(0)
  let destroyed = cell.new([])
  let moved = cell.new([])
  let seen = cell.new([])
  let rows =
    keyed.new(
      runtime,
      owner,
      fn(item: #(String, Int)) { item.0 },
      fn(value) {
        let id = cell.read(created)
        cell.write(created, id + 1)
        r.effect(runtime, fn() {
          cell.write(seen, [#(id, r.read(value).1), ..cell.read(seen)])
        })
        id
      },
      fn(id, index) { cell.write(moved, [#(id, index), ..cell.read(moved)]) },
      fn(id) { cell.write(destroyed, [id, ..cell.read(destroyed)]) },
    )
  keyed.update(rows, [#("a", 1), #("b", 2)])
  keyed.update(rows, [#("b", 3), #("a", 1)])
  keyed.get(rows, "b") |> should.equal(Ok(1))
  keyed.get(rows, "a") |> should.equal(Ok(0))
  cell.read(created) |> should.equal(2)
  cell.read(seen) |> should.equal([#(1, 3), #(1, 2), #(0, 1)])
  keyed.update(rows, [#("b", 3)])
  cell.read(destroyed) |> should.equal([0])
  keyed.get(rows, "a") |> should.be_error
  r.dispose(owner)
  cell.read(destroyed) |> should.equal([1, 0])
  cell.read(moved) |> list.take(3) |> should.equal([#(1, 0), #(0, 1), #(1, 0)])
}

pub fn queued_parent_disposes_old_child_before_it_can_rerun_test() {
  let runtime = r.new()
  let owner = r.scope(runtime)
  let source = r.signal(runtime, 0)
  let seen = cell.new([])
  r.within(runtime, owner, fn() {
    r.effect(runtime, fn() {
      let generation = r.read(source)
      r.effect(runtime, fn() {
        cell.write(seen, [#(generation, r.read(source)), ..cell.read(seen)])
      })
      Nil
    })
  })
  r.write(source, 1)
  r.dispose(owner)
  cell.read(seen) |> should.equal([#(1, 1), #(0, 0)])
}
