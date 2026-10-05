//// Type checking for the code an agent runs.
////
//// Resolving references is left to the platform, these functions work on inferred types.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleam/list
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

/// The type of the context in the type of a checked config.
/// A config without a context field gives a context of any type.
pub fn context(config: binding.Poly) -> binding.Poly {
  let level = 1
  let #(config, bindings) = binding.instantiate(config, level, dict.new())
  let config = binding.resolve(config, bindings)
  case config {
    t.Record(row) ->
      case find(row, "context") {
        Ok(context) -> binding.gen(context, level - 1, bindings)
        Error(Nil) -> t.Var(#(True, 0))
      }
    _ -> t.Var(#(True, 0))
  }
}

fn find(row, label) {
  case row {
    t.RowExtend(l, field, _) if l == label -> Ok(field)
    t.RowExtend(_, _, rest) -> find(rest, label)
    _ -> Error(Nil)
  }
}
