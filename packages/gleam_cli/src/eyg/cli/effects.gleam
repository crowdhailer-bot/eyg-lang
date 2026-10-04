//// Effects handled by the CLI itself, rather than the computer platform in loam,
//// as they need CLI modules such as the overlay agent.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/cli/check
import eyg/cli/overlay
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/value
import gleam/dict
import gleam/option.{type Option}
import gleam/string
import loam/execute
import loam/source
import loam/system

/// Handle CLI effects performed by a program run with `run` or `script`.
///
/// - `Overlay(config)` starts an agent session with the config.
///   The config is not type checked, so the agent's code is checked with any context type.
///   It resumes with `Ok({})` when the session ends or `Error(reason)` for an invalid config.
/// - `TypeCheck(code)` type checks EYG source, resuming with `Ok(type)` or `Error(reason)`.
pub fn handle(
  return: system.Effect(
    #(
      Result(#(Option(execute.Value), execute.Scope), execute.Debug),
      execute.State,
    ),
  ),
  cwd: String,
) {
  use #(result, state) <- system.then(return)
  case result {
    Error(#(break.UnhandledEffect("Overlay", user_config), _meta, env, k)) -> {
      use outcome <- system.then(overlay.start(
        user_config,
        any_type,
        cwd,
        state,
      ))
      let value = case outcome {
        Ok(Nil) -> value.ok(value.unit())
        Error(reason) -> value.error(value.String(reason))
      }
      handle(execute.loop(block.resume(value, env, k), state), cwd)
    }
    Error(#(break.UnhandledEffect("TypeCheck", value.String(code)), _, env, k)) -> {
      use #(outcome, state) <- system.then(type_check(code, cwd, state))
      let value = case outcome {
        Ok(type_) -> value.ok(value.String(type_))
        Error(reason) -> value.error(value.String(reason))
      }
      handle(execute.loop(block.resume(value, env, k), state), cwd)
    }
    _ -> system.Done(#(result, state))
  }
}

/// The type of a program, rendered as text, or its parse or type errors.
/// Relative imports are given any type as the source has no directory.
fn type_check(code, cwd, state) {
  case source.parse(code, source.Inline) {
    Ok(source) -> {
      use #(type_, errors, state) <- system.map(check.check_from(
        source,
        cwd,
        infer.unpure(),
        state,
        check.AnyType,
      ))
      case errors {
        [] -> {
          let #(type_, _) = binding.instantiate(type_, 0, dict.new())
          #(Ok(debug.render_type(type_)), state)
        }
        _ -> #(Error(string.join(check.render_errors(errors), "\n")), state)
      }
    }
    Error(reason) -> system.Done(#(Error(reason), state))
  }
}

const any_type = t.Var(#(True, 0))
