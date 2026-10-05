import birdie
import eyg/cli/helpers
import eyg/cli/run
import gleam/javascript/promise
import gleam/string
import loam/sandbox
import loam/source
import loam/system
import simplifile

pub fn print_error_in_import_test() {
  use return <- promise.map(
    system.run(run.execute(
      source.File(
        "././././test/fixtures/../fixtures/bad_function_in_import.eyg",
      ),
      helpers.config,
    )),
  )
  let assert Error(reason) = return
  birdie.snap(reason, title: "error in imported function")
}

pub fn abort_in_nested_helper_test() {
  use return <- promise.map(
    system.run(run.execute(
      source.File("./test/fixtures/abort_main.eyg"),
      helpers.config,
    )),
  )
  let assert Error(reason) = return
  birdie.snap(reason, title: "abort in nested helper")
}

pub fn file_effects_are_source_relative_test() {
  use return <- promise.map(
    system.run(run.execute(
      source.File("./test/fixtures/source_relative/main.eyg"),
      helpers.config,
    )),
  )
  let assert Ok(0) = return
}

pub fn cwd_effect_allows_inline_code_to_read_invocation_files_test() {
  use return <- promise.map(
    system.run(run.execute(
      source.Code(
        "let cwd = match perform CWD({}) {
  Ok(cwd) -> { cwd }
  Error(_) -> { !never(perform Abort(\"unspecified cwd\")) }
}
let path = !string_append(cwd, \"/test/fixtures/hello.txt\")
match perform ReadFile({path, offset: 0, limit: 100}) {
  Ok(bytes) -> {
    match !equal(bytes, !string_to_binary(\"Hello, World!\")) {
      True(_) -> { 0 }
      False(_) -> { !never(perform Abort(\"wrong contents\")) }
    }
  }
  Error(reason) -> { !never(perform Abort(reason)) }
}",
      ),
      helpers.config,
    )),
  )
  let assert Ok(0) = return
}

pub fn inline_absolute_import_works_test() {
  let assert Ok(cwd) = simplifile.current_directory()
  let path = cwd <> "/test/fixtures/source_relative/value.eyg"
  let code = "let value = import \"" <> path <> "\"
match !equal(value, 5) {
  True(_) -> { 0 }
  False(_) -> { !never(perform Abort(\"wrong value\")) }
}"
  use return <- promise.map(
    system.run(run.execute(source.Code(code), helpers.config)),
  )
  let assert Ok(0) = return
}

pub fn invalid_overlay_config_resumes_with_error_test() {
  let code =
    "match perform Overlay({llm: 1, policy: {}, context: {}}) {
      Ok(_) -> { perform Abort(\"started\") }
      Error(reason) -> { reason }
    }"
  let sandbox = sandbox.sandbox() |> sandbox.with_cwd("/")
  let assert #(sandbox.Returned(Ok(0)), _) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(sandbox)
}

pub fn type_check_effect_test() {
  let code =
    "match perform TypeCheck(\"{api_key: \\\"x\\\"}\") {
      Ok(type_) -> { perform StandardOut(type_) }
      Error(reason) -> { perform Abort(reason) }
    }"
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_cwd("/"))
  assert sandbox.stdout == ["{api_key: String}"]
}

fn overlay_outcome(context) {
  let code =
    "match perform Overlay({llm: 1, policy: {}, context: " <> context <> "}) {
      Ok(_) -> { perform Abort(\"started\") }
      Error(reason) -> { perform StandardOut(reason) }
    }"
  let sandbox = sandbox.sandbox() |> sandbox.with_cwd("/")
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    run.execute(source.Code(code), helpers.config)
    |> sandbox.run(sandbox)
  let assert [reason] = sandbox.stdout
  reason
}

pub fn overlay_context_is_type_checked_test() {
  let reason = overlay_outcome("{add: (x) -> { !int_add(x, \"one\") }}")
  assert string.starts_with(reason, "error: invalid context:")
}

pub fn overlay_context_with_functions_is_typed_test() {
  let reason = overlay_outcome("{add: (x) -> { !int_add(x, 1) }}")
  assert string.starts_with(reason, "error: invalid overlay config")
}
