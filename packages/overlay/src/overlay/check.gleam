//// Type checking for overlay configuration and the code an agent runs.
////
//// Resolving references is left to the platform, these functions work on inferred types.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleam/list
import gleam/result
import overlay/policy
import touch_grass/interface

/// The inference context for the agent's code.
/// The context value is in scope and the platform effects are available.
pub fn agent(
  effects: List(interface.Interface(a, b)),
  context: binding.Poly,
) -> infer.Context {
  let base = infer.pure() |> infer.with_effects(interface.types(effects))
  // Aborting is handled by every harness.
  let infer.Context(env:, ..) as base = case
    list.any(effects, fn(effect) { effect.name == "Abort" })
  {
    True -> base
    False -> infer.with_effect(base, "Abort", t.String, t.Never)
  }
  infer.Context(..base, env: [#("context", context), ..env])
}

/// Check the type of a config, returning the type of the context.
///
/// Each policy field must be a pure function `(lift) -> Pass(lift) | Mock(lower)`
/// for the effect it is named after.
pub fn config(
  type_: binding.Poly,
  effects: List(interface.Interface(a, b)),
) -> Result(binding.Poly, List(String)) {
  let level = 1
  let #(type_, bindings) = binding.instantiate(type_, level, dict.new())
  let type_ = binding.resolve(type_, bindings)
  use policy <- result.try(field(type_, "policy"))
  use context <- result.try(field(type_, "context"))
  use bindings <- result.try(check_policy(policy, effects, level, bindings))
  let context = binding.resolve(context, bindings)
  Ok(binding.gen(context, level - 1, bindings))
}

fn field(type_, label) {
  case type_ {
    t.Record(row) ->
      case find(row, label) {
        Ok(field) -> Ok(field)
        Error(Nil) -> Error(["the config has no `" <> label <> "` field"])
      }
    _ ->
      Error(["the config should be a record but has type " <> debug.mono(type_)])
  }
}

fn find(row, label) {
  case row {
    t.RowExtend(l, field, _) if l == label -> Ok(field)
    t.RowExtend(_, _, rest) -> find(rest, label)
    _ -> Error(Nil)
  }
}

fn fields(row, acc) {
  case row {
    t.RowExtend(label, field, rest) -> fields(rest, [#(label, field), ..acc])
    _ -> list.reverse(acc)
  }
}

fn check_policy(policy, effects, level, bindings) {
  case policy {
    t.Record(row) -> {
      let #(bindings, errors) =
        list.fold(fields(row, []), #(bindings, []), fn(acc, field) {
          let #(bindings, errors) = acc
          let #(name, type_) = field
          case find_effect(effects, name) {
            Ok(interface.Interface(lift_type:, lower_type:, ..)) -> {
              let #(rest, bindings) = binding.mono(level, bindings)
              let decision =
                t.Union(t.RowExtend(
                  "Pass",
                  lift_type,
                  t.RowExtend("Mock", lower_type, rest),
                ))
              let expected = t.Fun(lift_type, t.Empty, decision)
              case unify.unify(expected, type_, level, bindings) {
                Ok(bindings) -> #(bindings, errors)
                Error(reason) -> #(bindings, [
                  "policy `"
                    <> name
                    <> "` should be a pure function "
                    <> debug.mono(t.Fun(
                    lift_type,
                    t.Empty,
                    t.union([#("Pass", lift_type), #("Mock", lower_type)]),
                  ))
                    <> ", "
                    <> debug.reason(reason),
                  ..errors
                ])
              }
            }
            Error(Nil) -> #(bindings, [
              "unknown policy field `" <> name <> "`",
              ..errors
            ])
          }
        })
      case errors {
        [] -> Ok(bindings)
        _ -> Error(list.reverse(errors))
      }
    }
    _ ->
      Error([
        "the policy should be a record but has type " <> debug.mono(policy),
      ])
  }
}

fn find_effect(effects: List(interface.Interface(a, b)), name) {
  list.find(effects, fn(effect: interface.Interface(a, b)) {
    policy.field_name(effect.name) == name
  })
}
