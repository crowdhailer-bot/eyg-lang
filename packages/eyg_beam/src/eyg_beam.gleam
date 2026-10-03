//// Check and run EYG programs from Erlang and Elixir hosts.
////
//// Types and values are the plain terms of `eyg/analysis/type_/isomorphic`
//// and `eyg/interpreter/value`. In Erlang the type `{name: String}` is
//// `{record, {row_extend, <<"name">>, string, empty}}` and the value
//// `{name: "Ada"}` is `{record, #{<<"name">> => {string, <<"Ada">>}}}`.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// Start and end offset of an expression in the source.
pub type Span =
  #(Int, Int)

pub type Type =
  t.Type(Int)

pub type Value =
  state.Value(Span)

/// An effect the host handles.
/// The label, the type a program lifts to the host and the type the host replies with.
pub type Effect =
  #(String, #(Type, Type))

/// A module a program refers to as `@name`, already evaluated and type checked.
pub opaque type Package {
  Package(type_: binding.Poly, value: Value)
}

/// Load a pure module from its IR JSON, i.e. an `index.eyg.json` file.
pub fn load_package(json: String) -> Result(Package, String) {
  use source <- result.try(
    json.parse(json, dag_json.decoder(#(0, 0)))
    |> result.replace_error("not valid EYG IR JSON"),
  )
  let analysis = analyse(source, [], dict.new())
  use Nil <- result.try(case infer.all_errors(analysis) {
    [] -> Ok(Nil)
    [#(_, reason), ..] -> Error(type_debug.render_reason(reason))
  })
  case expression.execute(source, []) {
    Ok(value) -> Ok(Package(infer.poly_type(analysis), value))
    Error(#(reason, _, _, _)) -> Error(simple_debug.describe(reason))
  }
}

/// Parse a program without checking it, useful for checking only complete programs as they are typed.
pub fn parse(source: String) -> Result(Nil, String) {
  case parser.all_from_string(source) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(parser.format_error(reason, source))
  }
}

/// Type check a program, allowing only the host's effects.
/// Returns the type of the program or every error rendered against the source.
pub fn check(
  source: String,
  effects: List(Effect),
  packages: Dict(String, Package),
) -> Result(String, String) {
  use #(_tree, analysis) <- result.map(parse_and_check(
    source,
    effects,
    packages,
  ))
  type_debug.render_type(infer.type_(analysis))
}

/// Type check then run a program.
/// The handler is called with the label and lifted value of each effect,
/// it returns the value to resume the program with.
pub fn run(
  source: String,
  effects: List(Effect),
  packages: Dict(String, Package),
  handler: fn(String, Value) -> Value,
) -> Result(Value, String) {
  use #(tree, _analysis) <- result.try(parse_and_check(
    source,
    effects,
    packages,
  ))
  expression.execute(tree, [])
  |> loop(source, packages, handler)
}

/// Render a value as EYG source.
pub fn inspect(value: Value) -> String {
  simple_debug.inspect(value)
}

/// Render a type as EYG source.
pub fn render_type(type_: Type) -> String {
  type_debug.render_type(type_)
}

/// The type of a record with these fields.
pub fn record_type(fields: List(#(String, Type))) -> Type {
  t.record(fields)
}

/// The type of a union with these variants.
pub fn union_type(variants: List(#(String, Type))) -> Type {
  t.union(variants)
}

pub fn result_type(value: Type, reason: Type) -> Type {
  t.result(value, reason)
}

fn parse_and_check(source, effects, packages) {
  use tree <- result.try(
    parser.all_from_string(source)
    |> result.map_error(parser.format_error(_, source)),
  )
  let analysis = analyse(tree, effects, packages)
  case infer.all_errors(analysis) {
    [] -> Ok(#(tree, analysis))
    errors ->
      errors
      |> list.map(fn(error) {
        let #(span, reason) = error
        parser.render_error(
          type_debug.render_reason(reason),
          type_debug.hint(reason),
          source,
          span,
        )
      })
      |> string.join("\n\n")
      |> Error
  }
}

fn analyse(tree, effects, packages) {
  infer.pure()
  |> infer.with_effects(effects)
  |> infer.check(tree)
  |> resolve_types(packages)
}

fn resolve_types(step, packages) {
  case step {
    infer.Done(analysis) -> analysis
    infer.Lookup(reference:, resume:) ->
      lookup(packages, reference)
      |> result.map(fn(package: Package) { package.type_ })
      |> resume
      |> resolve_types(packages)
  }
}

fn loop(return, source, packages, handler) {
  case return {
    Ok(value) -> Ok(value)
    Error(#(break.UnhandledEffect(label, lift), _span, env, k)) ->
      expression.resume(handler(label, lift), env, k)
      |> loop(source, packages, handler)
    Error(#(break.UndefinedReference(reference) as reason, span, env, k)) ->
      case lookup(packages, reference) {
        Ok(package) ->
          expression.resume(package.value, env, k)
          |> loop(source, packages, handler)
        Error(Nil) -> Error(render_break(reason, source, span))
      }
    Error(#(reason, span, _env, _k)) ->
      Error(render_break(reason, source, span))
  }
}

fn lookup(packages: Dict(String, Package), reference) -> Result(Package, Nil) {
  case reference {
    ir.Package(package:) -> dict.get(packages, package)
    _ -> Error(Nil)
  }
}

fn render_break(reason, source, span) {
  parser.render_error(
    simple_debug.describe(reason),
    simple_debug.hint(reason),
    source,
    span,
  )
}
