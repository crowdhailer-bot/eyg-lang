import compile
import gleam/javascript/promise.{type Promise}
import gleam/string
import gleeunit
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

@external(javascript, "./njs_test_ffi.mjs", "handle")
fn handle(
  module: String,
  method: String,
  path: String,
) -> Promise(#(Int, String, String))

fn compiled() {
  let assert Ok(code) = simplifile.read("handler.eyg")
  let assert Ok(module) = compile.compile(code)
  module
}

pub fn every_builtin_the_handler_uses_is_compiled_test() {
  assert !string.contains(compiled(), "{ throw \"")
}

pub fn a_get_logs_and_asks_upstream_test() {
  use response <- promise.map(handle(compiled(), "GET", "/a/b"))
  assert response
    == #(
      200,
      "EYG handled 2 headers, path /a/b. Upstream said: from /upstream",
      "2 headers, path /a/b",
    )
}

pub fn other_methods_are_refused_test() {
  use response <- promise.map(handle(compiled(), "POST", "/"))
  let #(status, _, _) = response
  assert status == 405
}

pub fn a_handler_that_does_not_type_check_is_not_compiled_test() {
  let assert Error(_) = compile.compile("!int_add(1, \"x\")")
}
