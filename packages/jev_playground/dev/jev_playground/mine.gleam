//// Find the actions that build every definition in `eyg_packages` and mine the
//// most common compound moves from them.
//// `gleam run -m jev_playground/mine --runtime bun`

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/parser
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import jev_playground/action.{type Action}
import jev_playground/compound
import jev_playground/environment
import jev_playground/packages
import jev_playground/synthesis
import morph/editable as e
import plinth/javascript/performance
import simplifile

/// A top level definition of a file, built on its own.
pub type Definition {
  Definition(
    file: String,
    name: String,
    source: e.Expression,
    /// The typed variables in scope where the definition appears in its file.
    scope: List(#(String, binding.Poly)),
    bindings: dict.Dict(Int, binding.Binding),
  )
}

pub fn main() {
  let assert Ok(environment) = packages.environment()
  let definitions = definitions(environment)
  let results =
    list.map(definitions, fn(definition) {
      let start = performance.now()
      let environment =
        environment.Environment(
          ..environment,
          scope: definition.scope,
          bindings: definition.bindings,
        )
      let result = synthesis.script(definition.source, environment)
      let ms = float.round(performance.now() -. start)
      let outcome = case result {
        Ok(actions) -> int.to_string(list.length(actions)) <> " steps"
        Error(reason) -> reason
      }
      io.println_error(
        definition.file
        <> " "
        <> definition.name
        <> " "
        <> outcome
        <> " in "
        <> int.to_string(ms)
        <> "ms",
      )
      #(definition, result)
    })
  let scripts =
    list.filter_map(results, fn(result) {
      case result {
        #(definition, Ok(actions)) -> Ok(#(definition, actions))
        _ -> Error(Nil)
      }
    })
  let failures =
    list.filter_map(results, fn(result) {
      case result {
        #(definition, Error(reason)) -> Ok(#(definition, reason))
        _ -> Error(Nil)
      }
    })
  report(scripts, failures)
}

pub fn definitions(environment) -> List(Definition) {
  let assert Ok(files) = simplifile.get_files(packages.root)
  files
  |> list.filter(string.ends_with(_, ".eyg"))
  |> list.sort(string.compare)
  |> list.flat_map(fn(file) {
    let assert Ok(text) = simplifile.read(file)
    let name = string.replace(file, packages.root <> "/", "")
    case parser.all_from_string(text) {
      Ok(tree) -> split(name, e.from_annotated(tree), environment)
      Error(_) -> []
    }
  })
}

fn split(file, source, environment) {
  let analysis =
    infer.check_with_references(
      environment.context(environment),
      environment.references(environment),
      e.to_annotated(source, []),
    )
  let scope_at = fn(path) {
    infer.scope_at(analysis, list.reverse(path)) |> result.unwrap([])
  }
  let bindings = analysis.bindings
  case source {
    e.Block(assigns, then, _) ->
      list.index_map(assigns, fn(assign, i) {
        let #(pattern, value) = assign
        let name = case pattern {
          e.Bind(name) -> name
          e.Destructure(fields) ->
            "{" <> string.join(list.map(fields, fn(f) { f.1 }), ", ") <> "}"
        }
        Definition(file, name, value, scope_at([i, 1]), bindings)
      })
      |> list.append([
        Definition(
          file,
          "(module value)",
          then,
          scope_at([list.length(assigns)]),
          bindings,
        ),
      ])
    _ -> [Definition(file, "(module value)", source, [], bindings)]
  }
}

pub fn report(
  scripts: List(#(Definition, List(Action))),
  failures: List(#(Definition, String)),
) {
  let total = list.length(scripts) + list.length(failures)
  let steps = list.map(scripts, fn(s) { list.length(s.1) })
  let all_steps = int.sum(steps)
  io.println(
    "built "
    <> int.to_string(list.length(scripts))
    <> " of "
    <> int.to_string(total)
    <> " definitions in "
    <> int.to_string(all_steps)
    <> " steps",
  )
  failures
  |> list.map(fn(failure) { failure.1 })
  |> list.group(fn(reason) { reason })
  |> dict.map_values(fn(_, reasons) { list.length(reasons) })
  |> dict.to_list
  |> list.each(fn(entry) {
    io.println("  failed " <> int.to_string(entry.1) <> "x: " <> entry.0)
  })
  let largest =
    list.sort(scripts, fn(x, y) {
      int.compare(list.length(y.1), list.length(x.1))
    })
    |> list.take(5)
  io.println("largest:")
  list.each(largest, fn(script) {
    let #(definition, actions) = script
    io.println(
      "  "
      <> definition.file
      <> " "
      <> definition.name
      <> " "
      <> int.to_string(list.length(actions))
      <> " steps",
    )
  })
  let navigation =
    list.flat_map(scripts, fn(s) { s.1 })
    |> list.count(action.is_navigation)
  io.println("navigation is " <> percent(navigation, all_steps) <> " of steps")
  let found = compound.mine(list.map(scripts, fn(s) { s.1 }), 10)
  io.println("compounds:")
  list.each(found, fn(found) {
    io.println(
      "  saves "
      <> int.to_string(compound.saving(found))
      <> " in "
      <> int.to_string(found.occurrences)
      <> " uses across "
      <> int.to_string(found.scripts)
      <> " definitions: "
      <> compound.describe(found.steps),
    )
  })
  let saved = int.sum(list.map(found, compound.saving))
  io.println(
    "the ten compounds save "
    <> int.to_string(saved)
    <> " steps, "
    <> percent(saved, all_steps),
  )
}

fn percent(part, whole) {
  let value = int.to_float(part) *. 100.0 /. int.to_float(int.max(whole, 1))
  float.to_string(float.to_precision(value, 1)) <> "%"
}
