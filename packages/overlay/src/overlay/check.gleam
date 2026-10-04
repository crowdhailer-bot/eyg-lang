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
import gleam/option.{None, Some}
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
  let state = option.from_result(find_record_field(type_, "state"))
  use bindings <- result.try(check_policy(
    policy,
    effects,
    state,
    level,
    bindings,
  ))
  use bindings <- result.try(case find_record_field(type_, "context_policy") {
    Ok(context_policy) ->
      check_policy(context_policy, effects, state, level, bindings)
    Error(Nil) -> Ok(bindings)
  })
  use bindings <- result.try(check_audit(type_, level, bindings))
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
      Error([
        "the config should be a record but has type "
        <> debug.render_type(type_),
      ])
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

fn check_policy(policy, effects, state, level, bindings) {
  case policy {
    t.Record(row) -> {
      let #(bindings, errors) =
        list.fold(fields(row, []), #(bindings, []), fn(acc, field) {
          let #(bindings, errors) = acc
          let #(name, type_) = field
          let found = case name {
            "reference" -> Ok(#(t.String, t.String))
            _ ->
              find_effect(effects, name)
              |> result.map(fn(effect: interface.Interface(a, b)) {
                #(effect.lift_type, effect.lower_type)
              })
          }
          case found {
            Ok(#(lift_type, lower_type)) -> {
              let #(rest, bindings) = binding.mono(level, bindings)
              let expected = rule_type(lift_type, lower_type, rest, state)
              case unify.unify(expected, type_, level, bindings) {
                Ok(bindings) -> #(bindings, errors)
                Error(reason) -> #(bindings, [
                  "policy `"
                    <> name
                    <> "` should be a pure function "
                    <> debug.render_type(rule_type(
                    lift_type,
                    lower_type,
                    t.Empty,
                    state,
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
        "the policy should be a record but has type "
        <> debug.render_type(policy),
      ])
  }
}

fn find_effect(effects: List(interface.Interface(a, b)), name) {
  list.find(effects, fn(effect: interface.Interface(a, b)) {
    policy.field_name(effect.name) == name
  })
}

fn ask(lower) {
  t.record([#("question", t.String), #("denied", lower)])
}

/// The record passed to the config's audit function for every effect.
pub fn audit_entry() {
  t.record([
    #("effect", t.String),
    #("input", t.String),
    #("decision", t.String),
  ])
}

fn check_audit(type_, level, bindings) {
  case find_record_field(type_, "audit") {
    Error(Nil) -> Ok(bindings)
    Ok(audit) -> {
      let #(eff, bindings) = binding.mono(level, bindings)
      let #(ret, bindings) = binding.mono(level, bindings)
      case unify.unify(t.Fun(audit_entry(), eff, ret), audit, level, bindings) {
        Ok(bindings) -> Ok(bindings)
        Error(reason) ->
          Error([
            "audit should be a function "
            <> debug.render_type(t.Fun(audit_entry(), t.Empty, t.unit))
            <> ", "
            <> debug.reason(reason),
          ])
      }
    }
  }
}

fn find_record_field(type_, label) {
  case type_ {
    t.Record(row) -> find(row, label)
    _ -> Error(Nil)
  }
}

/// The type of a policy rule, with state the rule is also given the state and returns the next state.
fn rule_type(lift, lower, rest, state) {
  let decision =
    t.Union(t.RowExtend(
      "Pass",
      lift,
      t.RowExtend("Mock", lower, t.RowExtend("Ask", ask(lower), rest)),
    ))
  case state {
    None -> t.Fun(lift, t.Empty, decision)
    Some(state) ->
      t.Fun(
        lift,
        t.Empty,
        t.Fun(
          state,
          t.Empty,
          t.record([#("decision", decision), #("state", state)]),
        ),
      )
  }
}

/// Check the type of a policy on its own, i.e. one entered in the browser.
pub fn policy(
  type_: binding.Poly,
  effects: List(interface.Interface(a, b)),
) -> Result(Nil, List(String)) {
  let level = 1
  let #(type_, bindings) = binding.instantiate(type_, level, dict.new())
  let type_ = binding.resolve(type_, bindings)
  check_policy(type_, effects, None, level, bindings)
  |> result.replace(Nil)
}
