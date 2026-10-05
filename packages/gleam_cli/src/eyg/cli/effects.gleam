//// Effects handled by the CLI itself, rather than the computer platform in loam,
//// as they need CLI modules such as the overlay agent.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/cli/check
import eyg/cli/overlay
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/value
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/string
import loam/execute
import loam/source
import loam/system

/// Handle CLI effects performed by a program run with `run` or `script`.
///
/// - `Overlay(config)` starts an agent session with the config.
///   The config is not type checked, the agent's code is checked against the type of the context value.
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
    Error(#(break.UnhandledEffect("Overlay", user_config), meta, env, k)) -> {
      use #(outcome, state) <- system.then(start(user_config, meta, cwd, state))
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

/// Start a session once the type of the config's context is known.
fn start(user_config, meta, cwd, state) {
  case cast.field("context", Ok, user_config) {
    Ok(context) -> {
      use #(context_type, state) <- system.then(value_type(
        context,
        meta,
        cwd,
        state,
      ))
      case context_type {
        Ok(context_type) -> {
          use outcome <- system.map(overlay.start(
            user_config,
            context_type,
            cwd,
            state,
          ))
          #(outcome, state)
        }
        Error(reason) ->
          system.Done(#(Error("error: invalid context: " <> reason), state))
      }
    }
    Error(_) ->
      system.Done(#(Error("error: invalid overlay config: no context"), state))
  }
}

/// The type of a value, found by type checking the value captured as code.
/// Functions are checked with the scope they captured,
/// their relative imports resolve from the file they were written in.
fn value_type(
  value: execute.Value,
  meta: source.Location,
  cwd: String,
  state: execute.State,
) -> system.Effect(#(Result(binding.Poly, String), execute.State)) {
  case capturable(value) {
    True -> {
      let code = capture.capture(value, meta)
      use #(type_, _, errors) <- system.map(check.check_from(
        code,
        cwd,
        infer.unpure(),
        state,
      ))
      let type_ = case errors {
        [] -> Ok(type_)
        _ -> Error(list.map(errors, check.render_error) |> string.join("\n"))
      }
      #(type_, state)
    }
    False ->
      system.Done(#(
        Error("it holds a continuation, which cannot be type checked"),
        state,
      ))
  }
}

/// A continuation, from handling an effect, has no source to check.
fn capturable(value) {
  case value {
    value.LinkedList(items) -> list.all(items, capturable)
    value.Record(fields) -> dict.values(fields) |> list.all(capturable)
    value.Tagged(_, inner) -> capturable(inner)
    value.Closure(_, _, env) -> list.all(env, fn(pair) { capturable(pair.1) })
    value.Partial(value.Resume(_), _) -> False
    value.Partial(_, args) -> list.all(args, capturable)
    value.Binary(_) | value.Integer(_) | value.String(_) -> True
  }
}

/// The type of a program, rendered as text, or its parse or type errors.
/// Relative imports resolve from the working directory.
fn type_check(code, cwd, state) {
  case source.parse(code, source.Inline) {
    Ok(source) -> {
      use #(type_, _, errors) <- system.map(check.check_from(
        source,
        cwd,
        infer.unpure(),
        state,
      ))
      case errors {
        [] -> {
          let #(type_, _) = binding.instantiate(type_, 0, dict.new())
          #(Ok(debug.render_type(type_)), state)
        }
        _ -> #(
          Error(list.map(errors, check.render_error) |> string.join("\n")),
          state,
        )
      }
    }
    Error(reason) -> system.Done(#(Error(reason), state))
  }
}
