//// Compound moves are sequences of actions that recur when writing programs.
//// Actions are abstracted, names and literals removed, so the same structural
//// edit counts together whatever it is called. Compounds are found by
//// repeatedly merging the most frequent adjacent pair, as byte pair encoding does.

import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jev_playground/action.{type Action} as a
import jev_playground/agent

/// A symbol in a script, a single action or a merged pair.
pub type Symbol {
  Single(Action)
  Pair(Symbol, Symbol)
}

/// A compound move found by mining, with how often it occurs.
pub type Found {
  Found(steps: List(Action), occurrences: Int, scripts: Int)
}

/// Remove names and literals so edits with the same structure are equal.
pub fn abstract(action: Action) -> Action {
  case action {
    a.Variable(_) -> a.Variable("")
    a.String(_) -> a.String("")
    a.Integer(_) -> a.Integer(0)
    a.Builtin(_) -> a.Builtin("")
    a.Tag(_) -> a.Tag("")
    a.Reference(_) -> a.Reference(ir.Package(""))
    a.OpenLibrary(_) -> a.OpenLibrary("")
    a.Record(labels) -> a.Record(list.map(labels, fn(_) { "" }))
    a.Function(_) -> a.Function("")
    a.Assign(_) -> a.Assign("")
    a.AssignBefore(_) -> a.AssignBefore("")
    a.Select(_) -> a.Select("")
    a.Overwrite(_) -> a.Overwrite("")
    a.Match(labels) -> a.Match(list.map(labels, fn(_) { "" }))
    a.Perform(_) -> a.Perform("")
    a.Handle(_) -> a.Handle("")
    a.InsertBefore(Some(_)) -> a.InsertBefore(Some(""))
    a.InsertAfter(Some(_)) -> a.InsertAfter(Some(""))
    a.Rename(_) -> a.Rename("")
    a.Destructure(fields) ->
      a.Destructure(list.map(fields, fn(_) { #("", "") }))
    a.JumpToError(_) -> a.JumpToError(0)
    a.Compound(name, steps) -> a.Compound(name, list.map(steps, abstract))
    _ -> action
  }
}

pub fn flatten(symbol: Symbol) -> List(Action) {
  case symbol {
    Single(action) -> [action]
    Pair(first, second) -> list.append(flatten(first), flatten(second))
  }
}

/// Mine `count` compounds from scripts of concrete actions.
pub fn mine(scripts: List(List(Action)), count: Int) -> List(Found) {
  let scripts =
    list.map(scripts, fn(script) {
      list.map(script, fn(action) { Single(abstract(action)) })
    })
  do_mine(scripts, count, [])
  |> list.reverse
}

fn do_mine(scripts, count, found) {
  case count {
    0 -> found
    _ -> {
      let pairs = count_pairs(scripts)
      let best =
        dict.to_list(pairs)
        |> list.sort(fn(x, y) { int.compare(y.1.0, x.1.0) })
        |> list.first
      case best {
        Ok(#(#(first, second), #(occurrences, _))) if occurrences > 1 -> {
          let merged = Pair(first, second)
          let scripts = list.map(scripts, replace(_, first, second, merged, []))
          let occurrences = count_symbol(scripts, merged)
          let in_scripts = list.count(scripts, list.contains(_, merged))
          let found = [Found(flatten(merged), occurrences, in_scripts), ..found]
          do_mine(scripts, count - 1, found)
        }
        _ -> found
      }
    }
  }
}

// Occurrences of each adjacent pair and the number of scripts containing it.
fn count_pairs(scripts) -> Dict(#(Symbol, Symbol), #(Int, Int)) {
  list.fold(scripts, dict.new(), fn(counts, script) {
    let pairs = list.window_by_2(script)
    let counts =
      list.fold(pairs, counts, fn(counts, pair) {
        dict.upsert(counts, pair, fn(existing) {
          case existing {
            Some(#(n, s)) -> #(n + 1, s)
            None -> #(1, 0)
          }
        })
      })
    list.unique(pairs)
    |> list.fold(counts, fn(counts, pair) {
      dict.upsert(counts, pair, fn(existing) {
        case existing {
          Some(#(n, s)) -> #(n, s + 1)
          None -> #(0, 1)
        }
      })
    })
  })
}

fn replace(script, first, second, merged, acc) {
  case script {
    [x, y, ..rest] if x == first && y == second ->
      replace(rest, first, second, merged, [merged, ..acc])
    [x, ..rest] -> replace(rest, first, second, merged, [x, ..acc])
    [] -> list.reverse(acc)
  }
}

fn count_symbol(scripts, symbol) {
  list.fold(scripts, 0, fn(total, script) {
    total + list.count(script, fn(s) { s == symbol })
  })
}

/// Steps saved by a compound, each occurrence replaces its steps with one choice.
pub fn saving(found: Found) -> Int {
  found.occurrences * { list.length(found.steps) - 1 }
}

/// A readable form of an abstract compound, slots are shown as `_`.
pub fn describe(steps: List(Action)) -> String {
  list.map(steps, fn(step) {
    a.key(step)
    |> string.replace("\"\"", "_")
    |> string.replace("(_)", "")
  })
  |> string.join(", ")
}

/// The ten compounds mined from building every definition in `eyg_packages`,
/// `gleam run -m jev_playground/mine` finds them again.
pub fn mined() -> List(List(Action)) {
  [
    [a.Variable(""), a.Select("")],
    [a.Call, a.Variable("")],
    [a.Variable(""), a.Select(""), a.Call],
    [a.Variable(""), a.NextVacant],
    [a.InsertBefore(None), a.InsertBefore(None)],
    [a.Variable(""), a.Select(""), a.Call, a.InsertBefore(None)],
    [a.Variable(""), a.Call],
    [a.Tag(""), a.Call],
    [a.Builtin(""), a.Call, a.Variable("")],
    [a.Variable(""), a.Call, a.Variable("")],
  ]
}

/// Rewrite a script to use the compounds offered at each step, preferring the longest.
/// The agent is stepped through the script so only offered compounds are used.
pub fn compress(script: List(Action), agent: agent.Agent) -> List(Action) {
  do_compress(script, agent, [])
}

fn do_compress(script, agent, acc) {
  case script {
    [] -> list.reverse(acc)
    [next, ..rest] -> {
      let found =
        agent.options(agent)
        |> list.filter_map(fn(option) {
          case option.action {
            a.Compound(steps:, ..) as compound ->
              case list.length(steps) <= list.length(script) {
                True ->
                  case list.take(script, list.length(steps)) == steps {
                    True -> Ok(#(compound, list.length(steps)))
                    False -> Error(Nil)
                  }
                False -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        })
        |> list.sort(fn(x, y) { int.compare(y.1, x.1) })
        |> list.first
      let #(action, rest) = case found {
        Ok(#(compound, length)) -> #(compound, list.drop(script, length))
        Error(Nil) -> #(next, rest)
      }
      case agent.take(agent, agent.scripted(action)) {
        Ok(agent) -> do_compress(rest, agent, [action, ..acc])
        // A compound that fails when applied is replaced by its steps.
        Error(_) ->
          case action {
            a.Compound(..) -> {
              let assert Ok(agent) = agent.take(agent, agent.scripted(next))
              do_compress(list.drop(script, 1), agent, [next, ..acc])
            }
            _ -> list.reverse(acc)
          }
      }
    }
  }
}
