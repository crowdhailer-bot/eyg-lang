import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/string
import helpdesk_browser/grammar
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  let assert Ok(data) =
    simplifile.read("../../../packages/vscode-eyg/syntaxes/eyg.tmLanguage.json")
  assert data == grammar.data
    as "Update the shared Phoenix grammar before bundling"
  let assert Ok(bun) = runtime.get()
  let assert Ok(_) = simplifile.create_directory_all("build/browser")
  let assert Ok(_) =
    simplifile.write(
      "build/browser/entry.mjs",
      "import { main } from '../dev/javascript/helpdesk_browser/helpdesk_browser.mjs';\nmain();\n",
    )
  let options =
    json.object([
      #("entrypoints", json.array(["build/browser/entry.mjs"], json.string)),
      #("target", json.string("browser")),
      #("format", json.string("esm")),
      #("minify", json.bool(True)),
    ])
    |> json.to_string
  use compiled <- promise.await(bundle.build(bun, options))
  let assert Ok(compiled) = compiled
  assert bundle.success(compiled) as string.join(bundle.logs(compiled), "\n")
  let assert [output] = bundle.outputs(compiled)
  use code <- promise.map(bundle.text(output))
  let assert Ok(_) = simplifile.create_directory_all("../priv/static/assets")
  let assert Ok(_) =
    simplifile.write("../priv/static/assets/admin_eyg.js", code)
  io.println("Bundled the Gleam AshAdmin editor")
}
