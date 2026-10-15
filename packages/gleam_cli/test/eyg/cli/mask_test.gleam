import eyg/cli/check
import eyg/cli/eval
import eyg/cli/helpers
import gleam/list
import gleam/string
import loam/sandbox
import loam/source
import simplifile

pub fn masked_expectations_with_two_effects_test() {
  let assert Ok(example) = simplifile.read("../../eyg_packages/aok/next.eyg")
  let read = "ReadFile((lift) -> { Ok(!string_to_binary(\"hi\")) })"
  let stdout = "StandardOut((lift) -> { {} })"
  let cases = [
    #(read <> ", " <> stdout, "Ok([])"),
    #(read, "Error(\"Unexpected stdout!\")"),
    #("", "Error(\"Unexpected Readfile\")"),
    #(stdout, "Error(\"unexpected readfile\")"),
    #(read <> ", " <> read, "Error(\"unexpected stdout\")"),
  ]
  list.each(cases, fn(example_case) {
    let #(expectations, expected) = example_case
    let code =
      string.replace(example, "[" <> read <> "]", "[" <> expectations <> "]")
    let assert #(sandbox.Returned(Ok(0)), _) =
      check.execute(source.Code(code), helpers.config)
      |> sandbox.run(sandbox.sandbox())
    let assert #(sandbox.Returned(Ok(0)), output) =
      eval.execute(source.Code(code), helpers.config)
      |> sandbox.run(sandbox.sandbox())
    assert output.stdout == [expected]
  })
}

pub fn masked_function_reply_example_test() {
  let assert Ok(code) = simplifile.read("../../eyg_packages/aok/another.eyg")
  let assert #(sandbox.Returned(Ok(0)), _) =
    check.execute(source.Code(code), helpers.config)
    |> sandbox.run(sandbox.sandbox())
  let assert #(sandbox.Returned(Ok(0)), output) =
    eval.execute(source.Code(code), helpers.config)
    |> sandbox.run(sandbox.sandbox())
  assert output.stdout == ["42"]
}
