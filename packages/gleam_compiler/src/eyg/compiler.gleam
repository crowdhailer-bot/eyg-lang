//// Compile EYG programs to JavaScript.

import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/compiler/anf
import eyg/compiler/evidence
import eyg/compiler/generator
import eyg/ir/tree

/// Compile with generalized evidence passing and every optimisation.
pub fn to_js(program, refs) {
  evidence(program, refs, evidence.default())
}

pub fn evidence(program, refs, options) {
  let #(typed, checked) = analyse(program, refs)
  typed
  |> anf.program(checked)
  |> evidence.render(options)
}

/// A program without effect row information, every call is checked.
pub fn unchecked(program, options) {
  program
  |> tree.map_annotation(fn(_) { t.Var(-1) })
  |> anf.program(False)
  |> evidence.render(options)
}

/// Compile effectful functions to JavaScript generators.
/// A program that does not type check makes every function a generator.
pub fn generator(program, refs) {
  let #(typed, checked) = analyse(program, refs)
  case checked {
    True -> anf.program(typed, True)
    False ->
      program
      |> tree.map_annotation(fn(_) { t.Var(-1) })
      |> anf.program(False)
  }
  |> generator.render
}

/// Annotate each node with its resolved type.
/// The second value is false if the program does not type check,
/// in which case the types can not be trusted to decide what may yield.
pub fn analyse(program, refs) {
  let analysis = j.check_with_references(j.unpure(), refs, program)
  let j.Analysis(bindings:, tree: exp, ..) = analysis
  let typed =
    tree.map_annotation(exp, fn(info) {
      let #(_, type_, _, _) = info
      binding.resolve(type_, bindings)
    })
  #(typed, j.all_errors(analysis) == [])
}
