//// Hosts own caches and implement effects; Gleam owns parsing, checking and evaluation.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/embedding/packages
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/parser
import gleam/list
import gleam/result
import gleam/string
import midas/continuation as k

pub fn parse(source) {
  parser.all_from_string(source)
  |> result.map(fn(_) { Nil })
  |> result.map_error(parser.format_error(_, source))
}

pub fn check(source, cache, loader, effects) {
  use #(checked, cache) <- k.then(prepare(source, cache, loader, effects))
  k.return(#(
    result.map(checked, fn(item) { debug.render_type(infer.type_(item.1)) }),
    cache,
  ))
}

pub fn run(source, cache, loader, effects, handle) {
  use #(checked, cache) <- k.then(prepare(source, cache, loader, effects))
  let result = {
    use #(tree, _) <- result.try(checked)
    execute(expression.execute(tree, []), source, cache, handle)
  }
  k.return(#(result, cache))
}

fn prepare(source, cache, loader, effects) {
  case parser.all_from_string(source) {
    Error(reason) ->
      k.return(#(Error(parser.format_error(reason, source)), cache))
    Ok(tree) -> {
      use loaded <- k.then(packages.prepare(tree, cache, loader))
      case loaded {
        Error(reason) -> k.return(#(Error(reason), cache))
        Ok(loaded) ->
          k.return(#(analyse(tree, source, loaded, effects), loaded))
      }
    }
  }
}

fn analyse(tree, source, cache, effects) {
  let context = infer.with_effects(infer.pure(), effects)
  let analysis = cache.infer_sync(infer.check(context, tree), cache)
  case infer.all_errors(analysis) {
    [] -> Ok(#(tree, analysis))
    errors ->
      Error(
        list.map(errors, fn(error) {
          parser.render_error(
            debug.render_reason(error.1),
            debug.hint(error.1),
            source,
            error.0,
          )
        })
        |> string.join("\n\n"),
      )
  }
}

fn execute(step, source, cache, handle) {
  case cache.static_loop(step, cache, expression.resume) {
    Ok(value) -> Ok(value)
    Error(#(break.UnhandledEffect(label, lift), _, env, stack)) -> {
      use reply <- result.try(handle(label, lift))
      execute(expression.resume(reply, env, stack), source, cache, handle)
    }
    Error(#(reason, span, _, _)) ->
      Error(parser.render_error(
        simple_debug.describe(reason),
        simple_debug.hint(reason),
        source,
        span,
      ))
  }
}

pub fn inspect(value) {
  simple_debug.inspect(value)
}
