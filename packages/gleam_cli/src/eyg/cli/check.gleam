import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/cli/internal/config
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/dict
import gleam/list
import loam/execute
import loam/source
import loam/system

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let context = infer.unpure()

  let state = execute.State(config.client.origin, cache.empty())
  use #(type_, errors, _state) <- system.then(check_from(
    source,
    cwd,
    context,
    state,
    Follow,
  ))

  use Nil <- system.then(
    system.each(list.map(render_errors(errors), system.stdout)),
  )

  case errors {
    [] -> {
      let #(type_, _) = binding.instantiate(type_, 0, dict.new())
      let type_ = debug.render_type(type_)
      use Nil <- system.then(system.stdout(type_))
      system.Done(Ok(0))
    }
    _ -> {
      Error("")
      |> system.Done
    }
  }
}

pub fn check_from(
  source: ir.Node(source.Location),
  cwd: String,
  context: infer.Context,
  state: execute.State,
  relative: Relative,
) -> system.Effect(
  #(binding.Poly, List(#(source.Location, error.Reason)), execute.State),
) {
  let #(dir, path) = case source.1.origin {
    source.Disk(path:) -> #(filepath.directory_name(path), path)
    // source without a file resolves imports against the working directory.
    source.Pipe -> #(cwd, "")
    source.Inline -> #(cwd, "")
    source.Repl -> #(cwd, "")
    source.Content(..) -> #(cwd, "")
    source.Release(..) -> #(cwd, "")
  }

  use #(poly, _type, errors, state) <- system.map(do_check_all(
    context,
    dir,
    source,
    [],
    [path],
    state,
    relative,
  ))
  #(poly, errors, state)
}

/// How relative references are checked.
/// Agent code may only read files allowed by its policy so imports are given any type,
/// and are checked by the policy when the code runs.
pub type Relative {
  Follow
  AnyType
}

/// Render type errors with the source they occur in.
pub fn render_errors(errors: Errors) -> List(String) {
  list.map(errors, fn(error) {
    let #(location, reason) = error
    parser.render_error(
      debug.render_reason(reason),
      debug.hint(reason),
      source.code(location),
      source.span(location),
    )
  })
}

pub type Errors =
  List(#(source.Location, error.Reason))

fn do_check_all(
  context: infer.Context,
  directory: String,
  source: #(ir.Expression(source.Location), source.Location),
  errors: Errors,
  visited: List(String),
  state: execute.State,
  relative: Relative,
) -> system.Effect(#(binding.Poly, binding.Mono, Errors, execute.State)) {
  check_loop(
    infer.check(context, source),
    context,
    directory,
    errors,
    visited,
    state,
    relative,
  )
}

fn check_loop(
  step: infer.Step(infer.Analysis(source.Location)),
  context: infer.Context,
  directory: String,
  errors: Errors,
  visited: List(String),
  state: execute.State,
  relative: Relative,
) -> system.Effect(#(binding.Poly, binding.Mono, Errors, execute.State)) {
  case step {
    infer.Done(analysis) ->
      system.Done(#(
        infer.poly_type(analysis),
        infer.type_(analysis),
        list.append(errors, infer.all_errors(analysis)),
        state,
      ))
    infer.Lookup(reference:, resume:) -> {
      case reference {
        ir.Content(..) | ir.Package(..) | ir.Version(..) | ir.Pinned(..) -> {
          // Load the module from the hub, the cache records its type.
          use #(_, state) <- system.then(execute.lookup(
            reference,
            source.Inline,
            state,
          ))
          let type_ = case cache.get_reference(state.cache, reference) {
            Ok(cache.Module(type_:, ..)) -> Ok(type_)
            Error(Nil) -> Error(Nil)
          }
          resume(type_)
          |> check_loop(context, directory, errors, visited, state, relative)
        }
        ir.Relative(..) if relative == AnyType ->
          resume(Ok(t.Var(#(True, 0))))
          |> check_loop(context, directory, errors, visited, state, relative)
        ir.Relative(location:) -> {
          let next = fn(type_, errors, state) {
            resume(type_)
            |> check_loop(context, directory, errors, visited, state, relative)
          }
          case system.resolve_relative(directory, location) {
            Ok(path) -> {
              case cycle_check(visited, path) {
                Ok(Nil) -> {
                  use code <- system.then(system.read_file(path))
                  case code {
                    Ok(code) ->
                      case source.parse_input(code, source.File(location)) {
                        Ok(dependency) -> {
                          let check =
                            do_check_all(
                              context,
                              filepath.directory_name(path),
                              dependency,
                              errors,
                              [path, ..visited],
                              state,
                              relative,
                            )
                          use #(poly, _type_, errors, state) <- system.then(
                            check,
                          )
                          next(Ok(poly), errors, state)
                        }
                        Error(_reason) -> next(Error(Nil), errors, state)
                      }
                    Error(_reason) -> next(Error(Nil), errors, state)
                  }
                }
                Error(_cycle) -> next(Error(Nil), errors, state)
              }
            }
            Error(_reason) -> next(Error(Nil), errors, state)
          }
        }
      }
    }
  }
}

pub fn cycle_check(visited, path) {
  do_cycle_check(visited, path, [])
}

fn do_cycle_check(visited, path, acc) {
  case visited {
    [] -> Ok(Nil)
    [parent, ..] if parent == path -> Error([path, ..acc])
    [parent, ..rest] -> do_cycle_check(rest, path, [parent, ..acc])
  }
}
