import eyg/cli/check
import eyg/cli/helpers
import gleam/list
import gleam/string
import loam/sandbox
import loam/source
import simplifile

pub fn aok_entry_and_all_imported_tests_typecheck_test() {
  let root = "../../eyg_packages/aok/"
  let assert Ok(names) = simplifile.read_directory(root)
  let files =
    names
    |> list.filter(string.ends_with(_, ".eyg"))
    |> list.map(fn(name) {
      let assert Ok(code) = simplifile.read(root <> name)
      #("/aok/" <> name, code)
    })
  let input = source.Code("let _ = import \"/aok/entry.eyg\" {}")
  let assert #(sandbox.Returned(result), output) =
    check.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_files(files))
  assert output.stdout == ["{}"]
  assert result == Ok(0)
}
