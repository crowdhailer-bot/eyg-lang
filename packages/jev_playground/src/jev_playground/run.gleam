//// Evaluate programs, resolving library references and running their tests.
//// A test is a record `{name: String, test: (_) -> Boolean}` in the `tests`
//// field of the program, it passes when it returns `True({})`.

import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import jev_playground/environment.{type Environment}

pub type Outcome {
  Passed(name: String)
  Failed(name: String, reason: String)
}

pub type Value =
  state.Value(List(Int))

/// Evaluate a program to a value, effects are not allowed.
pub fn evaluate(
  source: ir.Node(List(Int)),
  environment: Environment,
) -> Result(Value, String) {
  state.step(state.E(source), builtin.default([]), state.Empty)
  |> finish(budget, environment)
}

/// Call a function value with arguments, effects are not allowed.
pub fn call(
  func: Value,
  args: List(Value),
  environment: Environment,
) -> Result(Value, String) {
  let env = builtin.default([])
  let k =
    list.fold_right(args, state.Empty, fn(k, arg) {
      state.Stack(state.CallWith(arg, env), [], k)
    })
  state.step(state.V(func), env, k)
  |> finish(budget, environment)
}

/// Programs Jev writes may never finish, for example when a recursive call does
/// not count down, so evaluation stops after this many steps.
const budget = 1_000_000

fn finish(next, remaining, environment) {
  case next {
    state.Loop(c, e, k) if remaining > 0 ->
      finish(state.step(c, e, k), remaining - 1, environment)
    state.Loop(..) -> Error("the program did not finish within a million steps")
    state.Break(Ok(value)) -> Ok(value)
    state.Break(Error(#(
      break.UndefinedReference(ir.Pinned(ir.Release(module:, ..)) as reference),
      _,
      env,
      k,
    )))
    | state.Break(Error(#(
        break.UndefinedReference(ir.Content(module) as reference),
        _,
        env,
        k,
      ))) ->
      case environment.library_by_module(environment, module) {
        Ok(library) ->
          finish(
            state.step(state.V(library.value), env, k),
            remaining,
            environment,
          )
        Error(Nil) ->
          Error("unknown reference " <> ir.reference_to_string(reference))
      }
    state.Break(Error(#(break.UnhandledEffect(label, _lift), _, _, _))) ->
      Error("the effect " <> label <> " was performed but is not handled")
    state.Break(Error(#(reason, _, _, _))) ->
      Error(simple_debug.describe(reason))
  }
}

pub fn tests(
  source: ir.Node(List(Int)),
  environment: Environment,
) -> Result(List(Outcome), String) {
  use program <- result.try(evaluate(source, environment))
  use tests <- result.try(case program {
    v.Record(fields) ->
      dict.get(fields, "tests")
      |> result.replace_error("the program has no `tests` field")
    _ -> Error("the program is not a record with a `tests` field")
  })
  use tests <- result.try(case tests {
    v.LinkedList(tests) -> Ok(tests)
    _ -> Error("`tests` is not a list")
  })
  Ok(list.index_map(tests, fn(test_, i) { run_test(test_, i, environment) }))
}

fn run_test(test_, i, environment) {
  let fallback = "test " <> int.to_string(i + 1)
  case test_ {
    v.Record(fields) -> {
      let name = case dict.get(fields, "name") {
        Ok(v.String(name)) -> name
        _ -> fallback
      }
      case dict.get(fields, "test") {
        Ok(func) ->
          case call(func, [v.unit()], environment) {
            Ok(v.Tagged("True", _)) -> Passed(name)
            Ok(v.Tagged("False", _)) -> Failed(name, "returned False")
            Ok(other) ->
              Failed(
                name,
                "returned " <> simple_debug.inspect(other) <> " not True({})",
              )
            Error(reason) -> Failed(name, reason)
          }
        Error(Nil) -> Failed(name, "the test has no `test` function")
      }
    }
    _ -> Failed(fallback, "a test must be a record of `name` and `test`")
  }
}

pub fn summary(outcomes: List(Outcome)) -> String {
  let passed = list.count(outcomes, fn(o) { o == Passed(o.name) })
  let failures =
    list.filter_map(outcomes, fn(outcome) {
      case outcome {
        Failed(name, reason) -> Ok(name <> ": " <> reason)
        Passed(_) -> Error(Nil)
      }
    })
  string.join(
    [
      int.to_string(passed)
        <> " of "
        <> int.to_string(list.length(outcomes))
        <> " tests passed",
      ..failures
    ],
    "\n",
  )
}
