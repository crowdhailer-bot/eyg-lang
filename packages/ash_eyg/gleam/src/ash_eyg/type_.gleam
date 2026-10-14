//// Ash introspection supplies shapes; EYG conversion is independent of Ash.

import eyg/analysis/type_/isomorphic as iso
import eyg/interpreter/value as v
import gleam/dict
import gleam/list

pub type HostValue

pub type Key

pub type Shape {
  Text
  Integer
  Boolean
  Choice(List(#(String, HostValue)))
  Array(Shape)
}

pub fn unit() {
  iso.Record(iso.Empty)
}

pub fn option(type_) {
  iso.union([#("Some", type_), #("None", unit())])
}

pub fn type_(shape: Shape, nullable: Bool) {
  let type_ = case shape {
    Text -> iso.String
    Integer -> iso.Integer
    Boolean -> iso.union([#("True", unit()), #("False", unit())])
    Choice(choices) ->
      iso.union(list.map(choices, fn(choice) { #(choice.0, unit()) }))
    Array(item) -> iso.List(type_(item, False))
  }
  case nullable {
    True -> option(type_)
    False -> type_
  }
}

pub fn encode(
  shape: Shape,
  nullable: Bool,
  value: HostValue,
) -> v.Value(m, context) {
  case nullable, is_null(value) {
    True, True -> v.Tagged("None", v.Record(dict.new()))
    True, False -> v.Tagged("Some", encode(shape, False, value))
    False, _ ->
      case shape {
        Text -> v.String(text(value))
        Integer -> v.Integer(integer(value))
        Boolean ->
          v.Tagged(
            case boolean(value) {
              True -> "True"
              False -> "False"
            },
            v.Record(dict.new()),
          )
        Choice(choices) -> {
          let assert Ok(choice) =
            list.find(choices, fn(choice) { choice.1 == value })
          v.Tagged(choice.0, v.Record(dict.new()))
        }
        Array(item) ->
          v.LinkedList(list.map(values(value), encode(item, False, _)))
      }
  }
}

pub fn decode(
  shape: Shape,
  nullable: Bool,
  value: v.Value(m, context),
) -> HostValue {
  case nullable, value {
    True, v.Tagged("None", _) -> null()
    True, v.Tagged("Some", value) -> decode(shape, False, value)
    _, _ ->
      case shape, value {
        Text, v.String(text) -> from_text(text)
        Integer, v.Integer(integer) -> from_integer(integer)
        Boolean, v.Tagged(tag, _) -> from_boolean(tag == "True")
        Choice(choices), v.Tagged(tag, _) -> {
          let assert Ok(choice) =
            list.find(choices, fn(choice) { choice.0 == tag })
          choice.1
        }
        Array(item), v.LinkedList(values) ->
          from_values(list.map(values, decode(item, False, _)))
        _, _ -> panic as "EYG input does not match its checked Ash type"
      }
  }
}

pub fn absent(value: v.Value(m, context)) {
  case value {
    v.Tagged("None", _) -> True
    _ -> False
  }
}

@external(erlang, "Elixir.AshEyg.Native", "is_null")
fn is_null(value: HostValue) -> Bool

@external(erlang, "Elixir.AshEyg.Native", "text")
fn text(value: HostValue) -> String

@external(erlang, "Elixir.AshEyg.Native", "integer")
fn integer(value: HostValue) -> Int

@external(erlang, "Elixir.AshEyg.Native", "boolean")
fn boolean(value: HostValue) -> Bool

@external(erlang, "Elixir.AshEyg.Native", "values")
fn values(value: HostValue) -> List(HostValue)

@external(erlang, "Elixir.AshEyg.Native", "null")
fn null() -> HostValue

@external(erlang, "Elixir.AshEyg.Native", "identity")
fn from_text(value: String) -> HostValue

@external(erlang, "Elixir.AshEyg.Native", "identity")
fn from_integer(value: Int) -> HostValue

@external(erlang, "Elixir.AshEyg.Native", "identity")
fn from_boolean(value: Bool) -> HostValue

@external(erlang, "Elixir.AshEyg.Native", "identity")
fn from_values(value: List(HostValue)) -> HostValue
