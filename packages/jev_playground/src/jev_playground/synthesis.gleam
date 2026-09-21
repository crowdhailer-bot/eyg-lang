//// Find a sequence of actions that builds a target program from an empty one.
//// The edits are simulated on a buffer so the script is exactly what an agent
//// would choose: holes are filled in reading order and navigation actions are
//// added whenever the selection is not already on the next hole.

import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result.{try}
import gleam/set
import jev_playground/action.{type Action} as a
import jev_playground/environment.{type Environment}
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/projection as p

type State {
  State(buffer: Buffer, environment: Environment, actions: List(Action))
}

/// The actions building `target` from `?` with the selection auto advancing.
pub fn script(
  target: e.Expression,
  environment: Environment,
) -> Result(List(Action), String) {
  let buffer =
    buffer.from_projection(
      p.all(e.Vacant),
      environment.context(environment),
      environment.references(environment),
    )
  let state = State(buffer:, environment:, actions: [])
  use state <- try(build(state, target, []))
  let built = p.rebuild(state.buffer.projection)
  case e.open_all(built) == e.open_all(target) {
    True -> Ok(list.reverse(state.actions))
    False -> Error("the script built a different program")
  }
}

fn step(state: State, action) -> Result(State, String) {
  case a.perform(action, state.buffer, state.environment, True) {
    Ok(buffer) ->
      Ok(State(..state, buffer:, actions: [action, ..state.actions]))
    Error(Nil) -> Error("could not " <> a.key(action))
  }
}

fn steps(state, actions) {
  list.try_fold(actions, state, step)
}

fn path(state: State) {
  p.path(state.buffer.projection)
}

const moves = [a.NextVacant, a.Next, a.Previous, a.Parent, a.Up, a.Down]

/// Move the selection to the node at `target` by the fewest navigation actions.
fn goto(state: State, target: List(Int)) -> Result(State, String) {
  case path(state) == target {
    True -> Ok(state)
    False -> {
      let start = #(state.buffer, [])
      use route <- try(search(
        [start],
        set.from_list([path(state)]),
        target,
        state,
        0,
      ))
      steps(state, route)
    }
  }
}

fn search(frontier, seen, target, state: State, depth) {
  case frontier, depth > 60 {
    [], _ | _, True -> Error("cannot navigate to " <> path_to_string(target))
    _, False -> {
      let next =
        list.flat_map(frontier, fn(entry) {
          let #(buffer, route) = entry
          list.filter_map(moves, fn(move) {
            use moved <- result.map(a.apply(move, buffer, state.environment))
            #(moved, [move, ..route])
          })
        })
      case
        list.find(next, fn(entry) { p.path({ entry.0 }.projection) == target })
      {
        Ok(#(_, route)) -> Ok(list.reverse(route))
        Error(Nil) -> {
          let #(next, seen) =
            list.fold(next, #([], seen), fn(acc, entry) {
              let #(keep, seen) = acc
              let key = p.path({ entry.0 }.projection)
              case set.contains(seen, key) {
                True -> acc
                False -> #([entry, ..keep], set.insert(seen, key))
              }
            })
          search(next, seen, target, state, depth + 1)
        }
      }
    }
  }
}

fn path_to_string(path) {
  "[" <> list.map(path, int.to_string) |> join <> "]"
}

fn join(parts) {
  case parts {
    [] -> ""
    [first, ..rest] ->
      list.fold(rest, first, fn(acc, part) { acc <> "," <> part })
  }
}

fn at(path, children) {
  list.append(path, children)
}

// The node at `path` is `?`, fill it with `target`.
fn build(state: State, target: e.Expression, path: List(Int)) {
  use state <- try(case target {
    e.Vacant -> Ok(state)
    _ -> goto(state, path)
  })
  case target {
    e.Vacant -> Ok(state)
    e.Variable(name) -> step(state, a.Variable(name))
    e.String(value) -> step(state, a.String(value))
    e.Integer(value) -> step(state, a.Integer(value))
    e.Builtin(name) -> step(state, a.Builtin(name))
    e.Tag(label) -> step(state, a.Tag(label))
    e.Reference(ref) -> reference(state, ref)
    e.Binary(_) -> Error("binary literals are not supported")
    e.Perform(_) | e.Deep(_) -> Error("unapplied effects are not supported")
    e.Call(e.Perform(label), [lift]) -> {
      use state <- try(step(state, a.Perform(label)))
      build(state, lift, at(path, [1]))
    }
    e.Call(e.Deep(label), [handler, exec]) ->
      handle(state, label, handler, exec, path)
    e.Call(func, args) -> call(state, func, args, path)
    e.Function(params, body) -> function(state, params, body, path)
    e.Block(assigns, then, _) -> block(state, assigns, then, path, 0)
    e.Record([], None) -> step(state, a.EmptyRecord)
    e.Record(fields, None) -> {
      use state <- try(step(state, a.Record(list.map(fields, fn(f) { f.0 }))))
      list.index_fold(fields, Ok(state), fn(state, field, i) {
        use state <- try(state)
        build(state, field.1, at(path, [i * 2 + 1]))
      })
    }
    e.Record([#(label, value)], Some(original)) -> {
      use state <- try(step(state, a.Overwrite(label)))
      use state <- try(build(state, value, at(path, [1])))
      build(state, original, at(path, [2]))
    }
    e.Record(_, Some(_)) -> Error("overwriting several fields is not supported")
    e.List([], None) -> step(state, a.EmptyList)
    e.List([], Some(_)) -> Error("a spread without items is not supported")
    e.List(items, tail) -> {
      let n = list.length(items)
      use state <- try(step(state, a.List))
      use state <- try(steps(state, list.repeat(a.InsertBefore(None), n - 1)))
      use state <- try(case tail {
        Some(_) -> step(state, a.Spread)
        None -> Ok(state)
      })
      use state <- try(
        list.index_fold(items, Ok(state), fn(state, item, i) {
          use state <- try(state)
          build(state, item, at(path, [i]))
        }),
      )
      case tail {
        Some(tail) -> build(state, tail, at(path, [n]))
        None -> Ok(state)
      }
    }
    e.Select(from, label) -> {
      use state <- try(build(state, from, path))
      use state <- try(goto(state, path))
      step(state, a.Select(label))
    }
    e.Case(top, matches, otherwise) ->
      match(state, top, matches, otherwise, path)
  }
}

fn reference(state: State, reference) {
  case reference {
    ir.Pinned(release) ->
      case environment.library_by_module(state.environment, release.module) {
        Ok(library) -> step(state, a.Reference(library.name))
        Error(Nil) -> Error("unknown library @" <> release.package)
      }
    _ -> Error("only pinned library references are supported")
  }
}

fn call(state: State, func, args, path) {
  use state <- try(build(state, func, path))
  use state <- try(goto(state, path))
  let arity =
    buffer.target_arity(state.buffer) |> result.unwrap(1) |> int.max(1)
  use state <- try(step(state, a.Call))
  let n = list.length(args)
  use state <- try(case n > arity {
    True -> steps(state, list.repeat(a.InsertBefore(None), n - arity))
    False -> Ok(state)
  })
  use state <- try(case n < arity {
    True -> {
      use state <- try(goto(state, at(path, [n + 1])))
      steps(state, list.repeat(a.Delete, arity - n))
    }
    False -> Ok(state)
  })
  list.index_fold(args, Ok(state), fn(state, arg, i) {
    use state <- try(state)
    build(state, arg, at(path, [i + 1]))
  })
}

fn function(state, params, body, path) {
  use #(state, count) <- try(
    list.try_fold(params, #(state, 0), fn(acc, param) {
      let #(state, count) = acc
      case param {
        e.Bind(name) -> {
          use state <- try(step(state, a.Function(name)))
          Ok(#(state, count + 1))
        }
        e.Destructure(fields) -> {
          use state <- try(step(state, a.Function("_")))
          use state <- try(goto(state, at(path, [count])))
          use state <- try(step(state, a.Destructure(fields)))
          use state <- try(goto(state, at(path, [count + 1])))
          Ok(#(state, count + 1))
        }
      }
    }),
  )
  build(state, body, at(path, [count]))
}

fn block(state, assigns, then, path, i) {
  case assigns {
    [] -> build(state, then, at(path, [i]))
    [#(pattern, value), ..rest] -> {
      use state <- try(case i {
        0 -> goto(state, path)
        _ -> goto(state, at(path, [i]))
      })
      use state <- try(case pattern {
        e.Bind(name) -> step(state, a.Assign(name))
        e.Destructure(fields) -> {
          use state <- try(step(state, a.Assign("_")))
          use state <- try(goto(state, at(path, [i, 0])))
          step(state, a.Destructure(fields))
        }
      })
      use state <- try(build(state, value, at(path, [i, 1])))
      block(state, rest, then, path, i + 1)
    }
  }
}

fn handle(state, label, handler, exec, path) {
  use state <- try(step(state, a.Handle(label)))
  use state <- try(branch(state, handler, at(path, [1]), ["value", "resume"]))
  branch(state, exec, at(path, [2]), ["_"])
}

// A function created with default parameter names, rename them and build the body.
fn branch(state, target, path, defaults) {
  let same_arity = case target {
    e.Function(params, _) -> list.length(params) == list.length(defaults)
    _ -> False
  }
  case target, same_arity {
    e.Function(params, body), True -> {
      use state <- try(
        list.index_fold(
          list.zip(params, defaults),
          Ok(state),
          fn(state, pair, i) {
            use state <- try(state)
            case pair {
              #(e.Bind(name), default) if name == default -> Ok(state)
              #(e.Bind(name), _) -> {
                use state <- try(goto(state, at(path, [i])))
                step(state, a.Rename(name))
              }
              #(e.Destructure(fields), _) -> {
                use state <- try(goto(state, at(path, [i])))
                step(state, a.Destructure(fields))
              }
            }
          },
        ),
      )
      build(state, body, at(path, [list.length(params)]))
    }
    _, _ -> {
      use state <- try(goto(state, path))
      use state <- try(step(state, a.Delete))
      build(state, target, path)
    }
  }
}

fn match(state, top, matches: List(#(String, e.Expression)), otherwise, path) {
  use state <- try(build(state, top, path))
  use state <- try(goto(state, path))
  use state <- try(step(state, a.Match(list.map(matches, fn(m) { m.0 }))))
  let n = list.length(matches)
  use state <- try(case otherwise {
    Some(_) -> {
      use state <- try(goto(state, at(path, [1, 0, 1])))
      step(state, a.Spread)
    }
    None -> Ok(state)
  })
  use state <- try(
    list.index_fold(matches, Ok(state), fn(state, match, i) {
      use state <- try(state)
      branch(state, match.1, at(path, [i + 1, 0]), ["_"])
    }),
  )
  case otherwise {
    Some(otherwise) -> branch(state, otherwise, at(path, [n + 1]), ["_"])
    None -> Ok(state)
  }
}

/// How often each action is used in a script, most common first.
pub fn frequencies(actions: List(Action)) -> List(#(String, Int)) {
  list.fold(actions, dict.new(), fn(counts, action) {
    dict.upsert(counts, a.key(action), fn(count) { option.unwrap(count, 0) + 1 })
  })
  |> dict.to_list
  |> list.sort(fn(x, y) { int.compare(y.1, x.1) })
}
