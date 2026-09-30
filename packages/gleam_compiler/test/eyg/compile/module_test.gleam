import eyg/compiler
import eyg/parser
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}

@external(javascript, "./module_ffi.mjs", "evaluate")
fn evaluate(module: String, input: Dynamic) -> Promise(Dynamic)

fn compile(code) {
  let assert Ok(source) = parser.all_from_string(code)
  compiler.to_module(source, dict.new())
}

fn run(code, input, decoder, check) {
  let assert Ok(module) = compile(code)
  use result <- promise.map(evaluate(module, input))
  let assert Ok(value) = decode.run(result, decoder)
  check(value)
}

// The ffi runs the module with `Double` doubling, `Wait` answered by a promise.

pub fn a_pure_program_is_the_exported_value_test() {
  use value <- run(
    "!int_add(1, 2)",
    dynamic.nil(),
    decode.at(["sync"], decode.int),
  )
  assert value == 3
}

pub fn effects_are_answered_by_the_handlers_passed_to_run_test() {
  use value <- run(
    "let a = perform Double(2)\n!int_add(a, perform Double(10))",
    dynamic.nil(),
    decode.at(["sync"], decode.int),
  )
  assert value == 24
}

pub fn a_program_that_is_a_function_is_called_by_the_host_test() {
  use value <- run(
    "(x) -> { perform Double(x) }",
    dynamic.int(21),
    decode.at(["called"], decode.int),
  )
  assert value == 42
}

pub fn a_program_can_wait_on_its_host_test() {
  use value <- run(
    "let a = perform Wait(5)\n!int_add(a, 1)",
    dynamic.nil(),
    decode.at(["async"], decode.int),
  )
  assert value == 6
}

pub fn a_program_that_does_not_type_check_is_not_compiled_test() {
  let assert Error([_]) = compile("!int_add(1, \"two\")")
}

pub fn a_program_can_handle_its_own_effects_test() {
  use value <- run(
    "handle Local((n, resume) -> { resume(!int_add(n, 1)) }, (_) -> {
      perform Double(perform Local(20))
    })",
    dynamic.nil(),
    decode.at(["sync"], decode.int),
  )
  assert value == 42
}
