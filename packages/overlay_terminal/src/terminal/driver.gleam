//// A typed effect interpreter that gives the frontend terminal ownership.
//// Every nonterminal operation still runs through the existing Loam driver.

import gleam/dynamic.{type Dynamic}
import gleam/http/request
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/uri
import loam/system as s
import plinthx/browser/performance
import plinthx/javascript/string as js_string
import plinthx/node/util

pub type IO {
  IO(
    output: fn(String, Bool) -> Nil,
    prompt: fn(String) -> promise.Promise(String),
    fetch: fn(String) -> Nil,
  )
}

pub fn now() -> Float {
  let assert Ok(clock) = performance.get()
  performance.now(clock)
}

pub fn clean(text: String) -> String {
  util.strip_vt_control_characters(text)
}

pub fn error_message(error: Dynamic) -> String {
  js_string.convert(error) |> result.unwrap("Unknown JavaScript error")
}

pub fn drive(effect: s.Effect(a), io: IO) -> promise.Promise(a) {
  s.run_with_interactions(
    effect,
    s.Interactions(
      output: fn(text, error) { io.output(clean(text), error) },
      input: fn(text) {
        io.prompt(clean(text) |> string.split("\r") |> last) |> promise.map(Ok)
      },
      fetch: fn(request) { io.fetch(public_url(request)) },
    ),
  )
}

fn last(values) {
  case values {
    [] -> ""
    [value] -> value
    [_, ..rest] -> last(rest)
  }
}

fn public_url(req) {
  let parsed = request.to_uri(req)
  uri.to_string(uri.Uri(..parsed, userinfo: None, query: None, fragment: None))
}
