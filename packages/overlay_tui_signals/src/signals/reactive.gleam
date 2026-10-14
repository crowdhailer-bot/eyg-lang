//// Synchronous fine-grained reactivity in Gleam. Reads track dependencies;
//// writes invalidate the graph, then effects pull dirty memos in dependency
//// order. Batches defer effects, and scopes own computations and cleanup.
//// No Solid runtime, host bindings, VDOM, or event loop is involved here.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import terminal/cell.{type Cell}

pub opaque type Runtime {
  Runtime(
    next: Cell(Int),
    current: Cell(Option(Observer)),
    owner: Cell(Option(Scope)),
    depth: Cell(Int),
    flushing: Cell(Bool),
    pending: Cell(List(#(Int, fn() -> Nil))),
  )
}

pub opaque type Scope {
  Scope(
    id: Int,
    alive: Cell(Bool),
    children: Cell(Dict(Int, Scope)),
    cleanups: Cell(List(fn() -> Nil)),
    parent: Option(Scope),
  )
}

type Observer {
  Observer(
    id: Int,
    invalidate: fn() -> Nil,
    sources: Cell(Dict(Int, fn() -> Nil)),
  )
}

pub opaque type Signal(a) {
  Signal(read: fn() -> a, write: fn(a) -> Nil)
}

pub opaque type Memo(a) {
  Memo(read: fn() -> a)
}

pub fn new() {
  Runtime(
    cell.new(0),
    cell.new(None),
    cell.new(None),
    cell.new(0),
    cell.new(False),
    cell.new([]),
  )
}

fn unique(runtime: Runtime) {
  let id = cell.read(runtime.next)
  cell.write(runtime.next, id + 1)
  id
}

pub fn scope(runtime: Runtime) {
  let parent = cell.read(runtime.owner)
  let scope =
    Scope(
      unique(runtime),
      cell.new(True),
      cell.new(dict.new()),
      cell.new([]),
      parent,
    )
  case parent {
    Some(parent) ->
      cell.write(
        parent.children,
        dict.insert(cell.read(parent.children), scope.id, scope),
      )
    None -> Nil
  }
  scope
}

pub fn within(runtime: Runtime, scope: Scope, run: fn() -> a) -> a {
  let assert True = cell.read(scope.alive)
  let before = cell.read(runtime.owner)
  cell.write(runtime.owner, Some(scope))
  let value = run()
  cell.write(runtime.owner, before)
  value
}

pub fn on_cleanup(scope: Scope, cleanup: fn() -> Nil) {
  case cell.read(scope.alive) {
    True -> cell.write(scope.cleanups, [cleanup, ..cell.read(scope.cleanups)])
    False -> cleanup()
  }
}

pub fn dispose(scope: Scope) {
  case cell.read(scope.alive) {
    False -> Nil
    True -> {
      cell.write(scope.alive, False)
      clear_scope(scope)
      case scope.parent {
        Some(parent) ->
          cell.write(
            parent.children,
            dict.delete(cell.read(parent.children), scope.id),
          )
        None -> Nil
      }
    }
  }
}

fn clear_scope(scope: Scope) {
  list.each(dict.values(cell.read(scope.children)), dispose)
  cell.write(scope.children, dict.new())
  let cleanups = cell.read(scope.cleanups)
  cell.write(scope.cleanups, [])
  list.each(cleanups, fn(cleanup) { cleanup() })
}

fn disconnect(observer: Observer) {
  list.each(dict.values(cell.read(observer.sources)), fn(remove) { remove() })
  cell.write(observer.sources, dict.new())
}

fn track(runtime: Runtime, id: Int, observers: Cell(Dict(Int, Observer))) {
  case cell.read(runtime.current) {
    None -> Nil
    Some(observer) -> {
      cell.write(
        observers,
        dict.insert(cell.read(observers), observer.id, observer),
      )
      cell.write(
        observer.sources,
        dict.insert(cell.read(observer.sources), id, fn() {
          cell.write(observers, dict.delete(cell.read(observers), observer.id))
        }),
      )
    }
  }
}

fn invalidate(observers: Cell(Dict(Int, Observer))) {
  list.each(dict.values(cell.read(observers)), fn(observer) {
    observer.invalidate()
  })
}

pub fn signal(runtime: Runtime, initial: a) -> Signal(a) {
  let id = unique(runtime)
  let value = cell.new(initial)
  let observers = cell.new(dict.new())
  Signal(
    fn() {
      track(runtime, id, observers)
      cell.read(value)
    },
    fn(next) {
      case next == cell.read(value) {
        True -> Nil
        False -> {
          cell.write(value, next)
          invalidate(observers)
          flush(runtime)
        }
      }
    },
  )
}

pub fn read(signal: Signal(a)) -> a {
  signal.read()
}

pub fn write(signal: Signal(a), value: a) -> Nil {
  signal.write(value)
}

pub fn read_memo(memo: Memo(a)) -> a {
  memo.read()
}

/// Read without subscribing the active computation to those reads.
pub fn untrack(runtime: Runtime, run: fn() -> a) -> a {
  let before = cell.read(runtime.current)
  cell.write(runtime.current, None)
  let value = run()
  cell.write(runtime.current, before)
  value
}

fn run_observer(
  runtime: Runtime,
  observer: Observer,
  owner: Scope,
  run: fn() -> a,
) -> a {
  disconnect(observer)
  untrack(runtime, fn() { clear_scope(owner) })
  let before = cell.read(runtime.current)
  cell.write(runtime.current, Some(observer))
  let result = within(runtime, owner, run)
  cell.write(runtime.current, before)
  result
}

pub fn memo(runtime: Runtime, compute: fn() -> a) -> Memo(a) {
  let id = unique(runtime)
  let lifetime = scope(runtime)
  let owner = within(runtime, lifetime, fn() { scope(runtime) })
  let dirty = cell.new(True)
  let computing = cell.new(False)
  let cached = cell.new(None)
  let observers = cell.new(dict.new())
  let observer =
    Observer(
      id,
      fn() {
        case cell.read(dirty) {
          True -> Nil
          False -> {
            cell.write(dirty, True)
            invalidate(observers)
          }
        }
      },
      cell.new(dict.new()),
    )
  // Disconnect belongs to this computation's lifetime, not its rerun cleanup.
  on_cleanup(lifetime, fn() { disconnect(observer) })
  Memo(fn() {
    let assert True = cell.read(lifetime.alive)
    case cell.read(dirty) {
      True -> {
        let assert False = cell.read(computing)
        cell.write(computing, True)
        let value = run_observer(runtime, observer, owner, compute)
        cell.write(cached, Some(value))
        cell.write(dirty, False)
        cell.write(computing, False)
      }
      False -> Nil
    }
    track(runtime, id, observers)
    let assert Some(value) = cell.read(cached)
    value
  })
}

pub fn effect(runtime: Runtime, run: fn() -> Nil) -> fn() -> Nil {
  let id = unique(runtime)
  let lifetime = scope(runtime)
  let owner = within(runtime, lifetime, fn() { scope(runtime) })
  let scheduled = cell.new(False)
  let callback = cell.new(fn() { Nil })
  let observer =
    Observer(
      id,
      fn() {
        case cell.read(scheduled) || !cell.read(lifetime.alive) {
          True -> Nil
          False -> {
            cell.write(scheduled, True)
            cell.write(runtime.pending, [
              #(id, cell.read(callback)),
              ..cell.read(runtime.pending)
            ])
          }
        }
      },
      cell.new(dict.new()),
    )
  cell.write(callback, fn() {
    cell.write(scheduled, False)
    case cell.read(lifetime.alive) {
      False -> Nil
      True -> run_observer(runtime, observer, owner, run)
    }
  })
  on_cleanup(lifetime, fn() { disconnect(observer) })
  batch(runtime, cell.read(callback))
  fn() { dispose(lifetime) }
}

/// Register cleanup on the active computation, before rerun and on disposal.
pub fn cleanup(runtime: Runtime, run: fn() -> Nil) {
  let assert Some(owner) = cell.read(runtime.owner)
  on_cleanup(owner, run)
}

pub fn batch(runtime: Runtime, run: fn() -> a) -> a {
  cell.write(runtime.depth, cell.read(runtime.depth) + 1)
  let value = run()
  cell.write(runtime.depth, cell.read(runtime.depth) - 1)
  flush(runtime)
  value
}

fn flush(runtime: Runtime) {
  case cell.read(runtime.depth) > 0 || cell.read(runtime.flushing) {
    True -> Nil
    False -> {
      cell.write(runtime.flushing, True)
      drain(runtime)
      cell.write(runtime.flushing, False)
    }
  }
}

fn drain(runtime: Runtime) {
  case cell.read(runtime.pending) {
    [] -> Nil
    pending -> {
      cell.write(runtime.pending, [])
      // Owners are created before their children. Running in creation order
      // lets a parent dispose a stale queued child before that child runs.
      list.each(
        list.sort(pending, fn(a, b) { int.compare(a.0, b.0) }),
        fn(item) { item.1() },
      )
      drain(runtime)
    }
  }
}
