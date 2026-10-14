//// Load and validate a whole package batch before a host exposes its cache.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/ir/tree as ir
import gleam/list
import gleam/result
import midas/continuation as k
import midas/effect
import ogre/origin

pub type Loader(t) {
  Loader(hub: String, fetch: effect.Fetch(t), hash: effect.Hash(t))
}

/// A caller keeps its original cache if any fetch, evaluation or validation
/// fails. The cache returned by a successful batch can be retained between runs.
pub fn prepare(tree, cache, loader: Loader(t)) {
  let references = ir.list_references(tree)
  case available(references, cache) {
    Ok(_) -> k.return(Ok(cache))
    Error(_) -> {
      case origin.from_string(loader.hub) {
        Error(_) -> k.return(Error("invalid hub origin"))
        Ok(origin) -> {
          use first <- k.then(
            drain(cache.prepare(cache, tree), loader, origin, []),
          )
          case first {
            Error(reason) -> k.return(Error(reason))
            Ok(#(cache, trees)) -> {
              case queue(references, cache) {
                Error(reason) -> k.return(Error(reason))
                Ok(cache) -> {
                  use loaded <- k.then(drain(cache, loader, origin, trees))
                  k.return({
                    use #(cache, trees) <- result.try(loaded)
                    use _ <- result.try(available(references, cache))
                    validate(trees, cache)
                  })
                }
              }
            }
          }
        }
      }
    }
  }
}

fn available(references, cache) {
  list.try_each(references, fn(reference) {
    cache.get_reference(cache, reference)
    |> result.map(fn(_) { Nil })
    |> result.replace_error(missing(reference))
  })
}

fn missing(reference) {
  debug.render_reason(error.MissingReference(reference))
}

fn queue(references, cache) {
  list.try_fold(references, cache, fn(cache, reference) {
    use cid <- result.map(module_cid(reference, cache))
    cache.fetch(cache, cid)
  })
}

fn module_cid(reference, cache) {
  case reference {
    ir.Content(cid) -> Ok(cid)
    ir.Package(name) ->
      cache.package(cache, name)
      |> result.map(fn(entry) { entry.module })
      |> result.replace_error("package not found: " <> name)
    ir.Version(name, version) ->
      cache.unbound_release(cache, name, version)
      |> result.replace_error(missing(reference))
    ir.Pinned(release) -> {
      case cache.unbound_release(cache, release.package, release.version) {
        Ok(cid) if cid == release.module -> Ok(cid)
        _ -> Error(missing(reference))
      }
    }
    ir.Relative(path) -> Error("relative imports are not supported: " <> path)
  }
}

fn drain(cache, loader, origin, trees) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> k.return(Ok(#(cache, trees)))
    _ -> {
      use completed <- k.then(complete(actions, cache, loader, origin, trees))
      case completed {
        Error(reason) -> k.return(Error(reason))
        Ok(#(cache, trees)) -> drain(cache, loader, origin, trees)
      }
    }
  }
}

fn complete(actions, cache, loader: Loader(t), origin, trees) {
  case actions {
    [] -> k.return(Ok(#(cache, trees)))
    [action, ..rest] -> {
      use message <- k.then(cache.compute(
        action,
        origin,
        loader.fetch,
        loader.hash,
      ))
      case message {
        cache.PullPackagesCompleted(Error(reason))
        | cache.FetchModuleCompleted(_, Error(reason)) ->
          k.return(Error(reason))
        _ -> {
          let #(next, resolved) =
            cache.update(cache, message, fn(_) { #(0, 0) })
          let failures =
            list.filter_map(resolved, fn(item) {
              case item.1 {
                Error(reason) -> Ok(simple_debug.describe(reason))
                _ -> Error(Nil)
              }
            })
          case failures {
            [reason, ..] -> k.return(Error(reason))
            [] -> {
              let trees = case message {
                cache.FetchModuleCompleted(_, Ok(tree)) -> [tree, ..trees]
                _ -> trees
              }
              complete(rest, next, loader, origin, trees)
            }
          }
        }
      }
    }
  }
}

fn validate(trees, cache) {
  list.try_fold(trees, cache, fn(cache, tree) {
    let analysis = cache.infer_sync(infer.check(infer.pure(), tree), cache)
    case infer.all_errors(analysis) {
      [] -> Ok(cache)
      [#(_, reason), ..] ->
        Error("invalid package module: " <> debug.render_reason(reason))
    }
  })
}
