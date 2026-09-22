//// The libraries a program Jev writes may reference. They are fetched from the
//// hub like any other module and put in the agent's environment, so their
//// functions are offered as calls once the program references one.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/result
import jev_playground/environment
import jev_playground/library

/// Every library the cache holds, fetched by `fetch`.
pub fn available(cache: cache.Cache(List(Int))) -> List(environment.Library) {
  list.filter_map(releases(), pinned(_, cache))
}

/// Ask the cache for the modules of every library, so they are there when a
/// question is asked.
pub fn fetch(cache: cache.Cache(meta)) -> cache.Cache(meta) {
  list.fold(releases(), cache, fn(cache, release: ir.Release) {
    cache.fetch(cache, release.module)
  })
}

fn releases() {
  [library.standard_release()]
}

fn pinned(release: ir.Release, cache) -> Result(environment.Library, Nil) {
  let source = #(ir.Reference(ir.Content(release.module)), [])
  let analysis = cache.infer_sync(infer.check(infer.pure(), source), cache)
  use Nil <- result.try(case infer.all_errors(analysis) {
    [] -> Ok(Nil)
    _ -> Error(Nil)
  })
  use value <- result.try(
    expression.execute(source, [])
    |> cache.static_loop(cache, expression.resume)
    |> result.replace_error(Nil),
  )
  Ok(
    environment.Library(
      name: release.package,
      release:,
      type_: infer.poly_type(analysis),
      value:,
      readme: readme(value),
      source: #(ir.Reference(ir.Content(release.module)), Nil),
    ),
  )
}

fn readme(value) {
  case value {
    value.Record(fields) ->
      case dict.get(fields, "readme") {
        Ok(value.String(readme)) -> readme
        _ -> ""
      }
    _ -> ""
  }
}
