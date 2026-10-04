//// The context is the value in scope, as `context`, for every program the agent runs.

import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{type Option, None, Some}

/// The context's own instructions, if it is a record with a string `readme` field.
pub fn provided_readme(context: v.Value(m, c)) -> Option(String) {
  case context {
    v.Record(fields) ->
      case dict.get(fields, "readme") {
        Ok(v.String(readme)) -> Some(readme)
        _ -> None
      }
    _ -> None
  }
}

/// The instructions given to the agent about its context.
/// Without a readme the agent is told the type of the context, when it is known.
pub fn readme(context: v.Value(m, c), type_: Option(binding.Poly)) -> String {
  case provided_readme(context), type_ {
    Some(readme), _ -> readme
    None, Some(type_) -> {
      let #(type_, _) = binding.instantiate(type_, 0, dict.new())
      "The context has no readme, it has type:\n" <> debug.mono(type_)
    }
    None, None -> "The context has no readme."
  }
}
