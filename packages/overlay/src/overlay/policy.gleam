//// A policy decides how each effect performed by agent code is handled.
////
//// A policy is an EYG record with a function field for each effect it allows.
//// Fields are named as the effect label in snake case, i.e. `read_file` for `ReadFile`.
//// Each function receives the effect's lift value and returns either
//// `Pass(lift)` to perform the effect, possibly with a modified value,
//// or `Mock(lower)` to resume the program with a value without performing the effect.
////
//// Effects without a field are refused, except intrinsic effects that do no IO.

import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub type Policy(value) {
  Policy(rules: Dict(String, value))
}

pub type Rule(value) {
  /// Call the function with the lift value to get a decision.
  Apply(value)
  /// Effects that do no IO are always allowed.
  Unrestricted
  /// The policy has no field for this effect.
  Refused
}

/// The policy field name for an effect label, e.g. `ReadFile` -> `read_file`,
/// `CWD` -> `cwd` and `DecodeJSON` -> `decode_json`.
pub fn field_name(label: String) -> String {
  do_field_name(string.to_graphemes(label), "", "")
}

fn do_field_name(chars, previous, acc) {
  case chars {
    [] -> string.lowercase(acc)
    [char, ..rest] -> {
      let next = case rest {
        [next, ..] -> next
        [] -> ""
      }
      let boundary =
        is_upper(char)
        && previous != ""
        && { is_lower(previous) || is_upper(previous) && is_lower(next) }
      let acc = case boundary {
        True -> acc <> "_" <> char
        False -> acc <> char
      }
      do_field_name(rest, char, acc)
    }
  }
}

fn is_upper(char) {
  char != string.lowercase(char)
}

fn is_lower(char) {
  char != string.uppercase(char)
}

/// Decode a policy value for a harness with the given effect labels.
/// Every field must name one of the effects, so a typo is reported rather than ignored.
pub fn decode(
  value: v.Value(m, c),
  labels: List(String),
) -> Result(Policy(v.Value(m, c)), String) {
  case value {
    v.Record(fields) -> {
      let names =
        list.map([reference, ..labels], fn(label) {
          #(field_name(label), label)
        })
      dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(fn(field) {
        let #(name, rule) = field
        case list.key_find(names, name) {
          Ok(label) -> Ok(#(label, rule))
          Error(Nil) ->
            Error(
              "unknown policy field `"
              <> name
              <> "`, expected one of: "
              <> string.join(list.map(names, fn(n) { n.0 }), ", "),
            )
        }
      })
      |> result.map(fn(rules) { Policy(dict.from_list(rules)) })
    }
    _ ->
      Error("policy must be a record with a function for each allowed effect")
  }
}

/// The label of the rule for loading published references, the `reference` field.
/// It is given the reference as text, i.e. `@standard:1` or `#<cid>`, and returns
/// `Pass(reference)` to load it or `Mock(reason)` to deny it.
/// Without the field every reference is loaded, references are pure code.
pub const reference = "Reference"

/// Effects that do no IO and so need no policy.
pub const intrinsic = ["DecodeJSON", "EYGParse", "Hash"]

pub fn rule(policy: Policy(value), label: String) -> Rule(value) {
  case dict.get(policy.rules, label) {
    Ok(function) -> Apply(function)
    Error(Nil) ->
      case list.contains(intrinsic, label) {
        True -> Unrestricted
        False -> Refused
      }
  }
}

/// The message given to the agent when its code performs an effect the policy does not allow.
pub fn refused(label: String) -> String {
  "the "
  <> label
  <> " effect is not permitted, the policy has no `"
  <> field_name(label)
  <> "` field"
}

pub type Decision(value) {
  Pass(value)
  Mock(value)
  /// Ask the user, if they agree the effect is passed otherwise the program resumes with denied.
  Ask(question: String, denied: value)
}

/// Interpret the value returned by a policy function given state, `{decision, state}`.
pub fn stateful_decision(
  value: v.Value(m, c),
) -> Result(#(Decision(v.Value(m, c)), v.Value(m, c)), String) {
  case value {
    v.Record(fields) ->
      case dict.get(fields, "decision"), dict.get(fields, "state") {
        Ok(decision_value), Ok(state) ->
          decision(decision_value) |> result.map(fn(d) { #(d, state) })
        _, _ ->
          Error("a policy function with state must return {decision, state}")
      }
    _ -> Error("a policy function with state must return {decision, state}")
  }
}

/// Interpret the value returned by a policy function.
pub fn decision(
  value: v.Value(m, c),
) -> Result(Decision(v.Value(m, c)), String) {
  case value {
    v.Tagged("Pass", inner) -> Ok(Pass(inner))
    v.Tagged("Mock", inner) -> Ok(Mock(inner))
    v.Tagged("Ask", v.Record(fields)) ->
      case dict.get(fields, "question"), dict.get(fields, "denied") {
        Ok(v.String(question)), Ok(denied) -> Ok(Ask(question:, denied:))
        _, _ ->
          Error("Ask must be given a record with a question and denied value")
      }
    _ ->
      Error(
        "a policy function must return Pass(value), Mock(value) or Ask({question, denied})",
      )
  }
}
