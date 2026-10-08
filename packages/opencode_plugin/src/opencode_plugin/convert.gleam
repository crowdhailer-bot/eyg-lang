//// Move values between EYG and JavaScript host effects.
////
//// Records become objects, lists become arrays, `True`/`False` become booleans,
//// `None` becomes null and `Some(x)` becomes x.
//// Other tagged values become an object with a single key, `GET({})` is `{GET: {}}`.
//// Functions cannot cross to JavaScript and become null.

import eyg/interpreter/value as v
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import loam/execute

@external(javascript, "../opencode_plugin_ffi.mjs", "object")
fn object(entries: List(#(String, Dynamic))) -> Dynamic

@external(javascript, "../opencode_plugin_ffi.mjs", "array")
fn array(items: List(Dynamic)) -> Dynamic

@external(javascript, "../opencode_plugin_ffi.mjs", "identity")
fn unsafe(x: a) -> Dynamic

@external(javascript, "../opencode_plugin_ffi.mjs", "nil")
fn null() -> Dynamic

@external(javascript, "../opencode_plugin_ffi.mjs", "is_nullish")
fn is_nullish(x: Dynamic) -> Bool

pub fn to_js(value: execute.Value) -> Dynamic {
  case value {
    v.Integer(i) -> unsafe(i)
    v.String(s) -> unsafe(s)
    v.Binary(bytes) -> unsafe(bytes)
    v.LinkedList(items) -> array(list.map(items, to_js))
    v.Record(fields) ->
      fields
      |> dict.to_list
      |> list.map(fn(field) { #(field.0, to_js(field.1)) })
      |> object
    v.Tagged("True", v.Record(_)) -> unsafe(True)
    v.Tagged("False", v.Record(_)) -> unsafe(False)
    v.Tagged("None", v.Record(_)) -> null()
    v.Tagged("Some", inner) -> to_js(inner)
    v.Tagged(label, inner) -> object([#(label, to_js(inner))])
    v.Closure(..) | v.Partial(..) -> null()
  }
}

pub fn from_js(value: Dynamic) -> execute.Value {
  case is_nullish(value) {
    True -> v.unit()
    False ->
      case decode.run(value, decoder()) {
        Ok(value) -> value
        Error(_) -> v.String(dynamic.classify(value))
      }
  }
}

fn decoder() -> decode.Decoder(execute.Value) {
  decode.one_of(decode.int |> decode.map(v.Integer), [
    decode.string |> decode.map(v.String),
    decode.bool |> decode.map(v.bool),
    decode.bit_array |> decode.map(v.Binary),
    decode.list(decode.dynamic)
      |> decode.map(fn(items) { v.LinkedList(list.map(items, from_js)) }),
    decode.dict(decode.string, decode.dynamic)
      |> decode.map(fn(fields) {
        v.Record(dict.map_values(fields, fn(_, field) { from_js(field) }))
      }),
    decode.float |> decode.map(fn(_) { v.String("float") }),
  ])
}
