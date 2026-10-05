import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/parser
import gleam/dict
import gleam/list
import overlay/check
import touch_grass/interface

fn effects() {
  [
    interface.Interface(
      name: "Now",
      lift_type: t.unit,
      lower_type: t.Integer,
      decode: cast.as_unit(_, ""),
    ),
  ]
}

fn infer(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let assert infer.Done(analysis) =
    infer.unpure()
    |> infer.with_effects(interface.types(effects()))
    |> infer.check(source)
  assert [] == infer.all_errors(analysis)
  infer.poly_type(analysis)
}

fn show(poly) {
  let #(mono, _) = binding.instantiate(poly, 0, dict.new())
  debug.mono(mono)
}

pub fn context_type_test() {
  let type_ = infer("{llm: {}, policy: {}, context: {readme: \"hi\"}}")
  assert show(check.context(type_)) == "{readme: String}"
}

pub fn agent_code_uses_context_type_test() {
  let context =
    check.context(infer("{llm: {}, policy: {}, context: {count: 1}}"))
  let assert Ok(source) = parser.all_from_string("!int_add(context.count, 1)")
  let assert infer.Done(analysis) =
    check.agent(effects(), context) |> infer.check(source)
  assert [] == infer.all_errors(analysis)
  let assert Ok(source) = parser.all_from_string("context.missing")
  let assert infer.Done(analysis) =
    check.agent(effects(), context) |> infer.check(source)
  assert 1 == list.length(infer.all_errors(analysis))
}

pub fn agent_can_abort_test() {
  let assert Ok(source) = parser.all_from_string("perform Abort(\"stop\")")
  let assert infer.Done(analysis) =
    check.agent(effects(), t.unit) |> infer.check(source)
  assert [] == infer.all_errors(analysis)
}
