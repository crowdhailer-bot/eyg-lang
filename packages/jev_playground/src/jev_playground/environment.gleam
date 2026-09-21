//// The effects a program may perform and the libraries it may reference.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import multiformats/cid/v1
import touch_grass/harness/browser as harness
import touch_grass/interface

pub type Environment {
  Environment(
    effects: List(#(String, #(binding.Mono, binding.Mono))),
    libraries: List(Library),
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
  )
}

/// Every effect the browser runtime implements, and no libraries.
pub fn browser() -> Environment {
  Environment(effects: interface.types(harness.effects()), libraries: [])
}

pub fn pure() -> Environment {
  Environment(effects: [], libraries: [])
}

pub fn with_libraries(environment, libraries) {
  Environment(..environment, libraries:)
}

pub fn context(environment: Environment) -> infer.Context {
  infer.pure() |> infer.with_effects(environment.effects)
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
        <> debug.mono(lift)
        <> ") returns "
        <> debug.mono(lower),
    )
  })
}

pub fn render_poly(poly) {
  let #(type_, _) = binding.instantiate(poly, 0, dict.new())
  debug.mono(type_)
}
