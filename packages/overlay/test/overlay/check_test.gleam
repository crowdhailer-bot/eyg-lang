import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/parser
import gleam/dict
import gleam/list
import gleam/string
import overlay/check
import touch_grass/interface

fn effects() {
  [
    interface.Interface(
      name: "ReadFile",
      lift_type: t.String,
      lower_type: t.result(t.String, t.String),
      decode: cast.as_string,
    ),
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

fn context_type(poly) {
  let #(mono, _) = binding.instantiate(poly, 0, dict.new())
  debug.mono(mono)
}

pub fn valid_config_test() {
  let type_ =
    infer(
      "{
        llm: {},
        policy: {
          read_file: (path) -> { Mock(Error(path)) },
          now: (x) -> { Pass(x) }
        },
        context: {readme: \"hi\"}
      }",
    )
  let assert Ok(context) = check.config(type_, effects())
  assert context_type(context) == "{readme: String}"
}

pub fn wrong_mock_type_test() {
  let type_ =
    infer("{llm: {}, policy: {now: (_) -> { Mock(\"late\") }}, context: {}}")
  let assert Error([reason]) = check.config(type_, effects())
  assert string.starts_with(reason, "policy `now` should be a pure function")
}

pub fn effectful_policy_test() {
  let type_ =
    infer(
      "{llm: {}, policy: {now: (x) -> { let _ = perform Now({}) Pass(x) }}, context: {}}",
    )
  let assert Error([reason]) = check.config(type_, effects())
  assert string.starts_with(reason, "policy `now` should be a pure function")
}

pub fn unknown_field_test() {
  let type_ =
    infer("{llm: {}, policy: {exit: (x) -> { Pass(x) }}, context: {}}")
  assert check.config(type_, effects())
    == Error(["unknown policy field `exit`"])
}

pub fn missing_context_test() {
  let type_ = infer("{llm: {}, policy: {}}")
  assert check.config(type_, effects())
    == Error(["the config has no `context` field"])
}

pub fn agent_code_uses_context_type_test() {
  let assert Ok(context) =
    check.config(infer("{llm: {}, policy: {}, context: {count: 1}}"), effects())
  let assert Ok(source) = parser.all_from_string("!int_add(context.count, 1)")
  let assert infer.Done(analysis) =
    check.agent(effects(), context) |> infer.check(source)
  assert [] == infer.all_errors(analysis)
  let assert Ok(source) = parser.all_from_string("context.missing")
  let assert infer.Done(analysis) =
    check.agent(effects(), context) |> infer.check(source)
  assert 1 == list.length(infer.all_errors(analysis))
}

pub fn ask_policy_test() {
  let type_ =
    infer(
      "{llm: {}, policy: {now: (_) -> { Ask({question: \"time?\", denied: 0}) }}, context: {}}",
    )
  let assert Ok(_) = check.config(type_, effects())
}

pub fn audit_test() {
  let type_ =
    infer(
      "{llm: {}, policy: {}, context: {}, audit: (entry) -> { let _ = perform Now({}) entry.effect }}",
    )
  let assert Ok(_) = check.config(type_, effects())
  let type_ = infer("{llm: {}, policy: {}, context: {}, audit: 5}")
  let assert Error([reason]) = check.config(type_, effects())
  assert string.starts_with(reason, "audit should be a function")
}

pub fn context_policy_is_checked_test() {
  let type_ =
    infer(
      "{llm: {}, policy: {}, context: {}, context_policy: {now: (_) -> { Mock(\"late\") }}}",
    )
  let assert Error([reason]) = check.config(type_, effects())
  assert string.starts_with(reason, "policy `now` should be a pure function")
}

pub fn reference_rule_test() {
  let type_ =
    infer(
      "{llm: {}, policy: {reference: (ref) -> { match !equal(ref, \"@standard\") { True(_) -> { Pass(ref) } False(_) -> { Mock(\"untrusted\") } } }}, context: {}}",
    )
  let assert Ok(_) = check.config(type_, effects())
}

pub fn stateful_policy_test() {
  let type_ =
    infer(
      "{llm: {}, state: 0, policy: {now: (lift, count) -> { {decision: Pass(lift), state: !int_add(count, 1)} }}, context: {}}",
    )
  let assert Ok(_) = check.config(type_, effects())
  let type_ =
    infer(
      "{llm: {}, state: 0, policy: {now: (lift) -> { Pass(lift) }}, context: {}}",
    )
  let assert Error([_]) = check.config(type_, effects())
}
