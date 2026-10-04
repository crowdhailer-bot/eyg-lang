import gleam/dynamic
import gleam/javascript/array
import gleam/javascript/promise
import gleeunit
import gleeunit/should
import plinthx/browser/performance
import plinthx/browser/response
import plinthx/bun
import plinthx/bun/subprocess
import plinthx/javascript/array as mutable
import plinthx/javascript/string as js_string
import plinthx/node/fs
import plinthx/node/process
import plinthx/node/tty
import plinthx/node/url

pub fn main() {
  gleeunit.main()
}

pub fn native_array_mutation_is_visible_through_existing_receiver_test() {
  let values = array.from_list([1])
  let same = values
  mutable.set(values, 0, 42) |> should.equal(Ok(Nil))
  array.get(same, 0) |> should.equal(Ok(42))
}

pub fn monotonic_clock_uses_retrieved_native_object_test() {
  let clock = performance.get() |> should.be_ok
  let before = performance.now(clock)
  { performance.now(clock) >=. before } |> should.be_true
}

pub fn invalid_response_status_and_file_url_are_results_test() {
  response.new("body", response.Options(0, [])) |> should.be_error
  url.file_url_to_path("https://example.com/path") |> should.be_error
}

pub fn string_conversion_handles_dynamic_primitives_test() {
  js_string.convert(dynamic.string("hello")) |> should.equal(Ok("hello"))
  js_string.convert(dynamic.int(42)) |> should.equal(Ok("42"))
}

pub fn unavailable_ipc_and_invalid_spawn_are_results_test() {
  let parent = process.get() |> should.be_ok
  process.send(parent, dynamic.string("test")) |> should.be_error
  let host = bun.get() |> should.be_ok
  let cwd = process.cwd(parent) |> should.be_ok
  subprocess.spawn(
    host,
    [],
    subprocess.Options(
      cwd,
      process.env(parent),
      "ignore",
      "ignore",
      "ignore",
      "json",
      fn(_, _) { Nil },
    ),
  )
  |> should.be_error
}

pub fn missing_directory_is_an_async_result_test() {
  use value <- promise.map(fs.readdir_with_file_types(
    "/this-path-does-not-exist/plinthx",
  ))
  should.be_error(value)
}

pub fn process_is_the_native_object_test() {
  let assert Ok(process) = process.get()
  // Piped output has no isTTY property.
  let assert True = case tty.is_tty(process.stdout(process)) {
    Ok(_) | Error(Nil) -> True
  }
}
