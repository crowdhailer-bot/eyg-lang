//// The effects a program may perform and the libraries it may reference.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/string
import multiformats/cid/v1
import touch_grass/harness/browser as harness
import touch_grass/interface

pub type Environment {
  Environment(
    effects: List(#(String, #(binding.Mono, binding.Mono))),
    libraries: List(Library),
    /// Variables already defined around the program, with the bindings their types refer to.
    scope: List(#(String, binding.Poly)),
    /// The values of the variables in `scope`, when the program is run.
    values: List(#(String, state.Value(List(Int)))),
    bindings: Dict(Int, binding.Binding),
  )
}

/// A published package, referenced in code by its pinned release.
pub type Library {
  Library(
    name: String,
    release: ir.Release,
    type_: binding.Poly,
    value: state.Value(List(Int)),
    readme: String,
    source: ir.Node(Nil),
  )
}

/// Every effect the browser runtime implements, and no libraries.
pub fn browser() -> Environment {
  Environment(
    effects: interface.types(harness.effects()),
    libraries: [],
    scope: [],
    values: [],
    bindings: dict.new(),
  )
}

pub fn pure() -> Environment {
  Environment(
    effects: [],
    libraries: [],
    scope: [],
    values: [],
    bindings: dict.new(),
  )
}

pub fn with_libraries(environment, libraries) {
  Environment(..environment, libraries:)
}

pub fn context(environment: Environment) -> infer.Context {
  let Environment(scope:, bindings:, ..) = environment
  infer.Context(scope, t.Empty, 1, bindings)
  |> infer.with_effects(environment.effects)
}

pub fn references(environment: Environment) -> Dict(v1.Cid, binding.Poly) {
  list.map(environment.libraries, fn(library) {
    #(library.release.module, library.type_)
  })
  |> dict.from_list
}

pub fn find_library(environment: Environment, name) {
  list.find(environment.libraries, fn(library) { library.name == name })
}

pub fn library_by_module(environment: Environment, cid) {
  list.find(environment.libraries, fn(library) { library.release.module == cid })
}

/// Effect names with their lift and lower types, as shown to Jev.
pub fn effect_signatures(environment: Environment) -> List(#(String, String)) {
  list.map(environment.effects, fn(effect) {
    let #(label, #(lift, lower)) = effect
    #(
      label,
      "perform "
        <> label
        <> "("
        <> show_type(lift)
        <> ") returns "
        <> show_type(lower),
    )
  })
}

pub fn render_poly(poly) {
  let #(type_, _) = binding.instantiate(poly, 0, dict.new())
  show_type(type_)
}

/// The fields of a library with their types, nested records are flattened to
/// `operation.get` so each function is listed on its own.
pub fn library_api(library: Library) -> List(#(String, String)) {
  let #(type_, _) = binding.instantiate(library.type_, 0, dict.new())
  flatten(type_, "", 2)
}

fn flatten(type_, prefix, depth) {
  case type_ {
    t.Record(rows) if depth > 0 ->
      rows_of(rows, [])
      |> list.flat_map(fn(field) {
        let #(label, value) = field
        flatten(value, prefix <> label <> ".", depth - 1)
      })
    _ ->
      case prefix {
        "" -> []
        _ -> [#(string.drop_end(prefix, 1), show_type(type_))]
      }
  }
}

fn rows_of(rows, acc) {
  case rows {
    t.RowExtend(label, value, rest) -> rows_of(rest, [#(label, value), ..acc])
    _ -> list.reverse(acc)
  }
}

/// A type as shown to Jev: effect rows are left out and type variables are
/// letters, `(List(116) <..117>) -> 116` becomes `(List(a)) -> a`.
pub fn show_type(type_) -> String {
  let text = debug.mono(type_)
  let assert Ok(effects) = regexp.from_string(" <[^<>]*>")
  let text = regexp.replace(effects, text, "")
  let assert Ok(numbers) = regexp.from_string("\\b[0-9]+\\b")
  let found =
    regexp.scan(numbers, text)
    |> list.map(fn(match) { match.content })
    |> list.unique
  list.index_fold(found, text, fn(text, number, i) {
    let assert Ok(exact) = regexp.from_string("\\b" <> number <> "\\b")
    regexp.replace(exact, text, letter(i))
  })
}

fn letter(i) {
  let letters = string.to_graphemes("abcdefghijklmnopqrstuvwxyz")
  case list.drop(letters, i % 26) |> list.first, i / 26 {
    Ok(l), 0 -> l
    Ok(l), n -> l <> int.to_string(n)
    Error(Nil), _ -> "t"
  }
}

/// The readme of the module in scope as `context`, if it has one.
pub fn context_readme(environment: Environment) -> Option(String) {
  case list.key_find(environment.values, "context") {
    Ok(v.Record(fields)) ->
      case dict.get(fields, "readme") {
        Ok(v.String(readme)) -> Some(readme)
        _ -> None
      }
    _ -> None
  }
}

/// The labels of the effects in an effect row, `DNSimple` or `Abort`.
pub fn effect_labels(row) -> List(String) {
  case row {
    t.EffectExtend(label, _, rest) -> [label, ..effect_labels(rest)]
    _ -> []
  }
}

/// The effects a function performs when it is given all its arguments.
pub fn performs(type_, arity) -> List(String) {
  case type_, arity {
    t.Fun(_, effect, return), n if n > 1 ->
      list.append(effect_labels(effect), performs(return, n - 1))
    t.Fun(_, effect, _), _ -> effect_labels(effect)
    _, _ -> []
  }
  |> list.unique
}
