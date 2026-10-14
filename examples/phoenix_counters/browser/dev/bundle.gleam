import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/string
import grammar
import icons
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  grammar.check()
  icons.main()
  let assert Ok(bun) = runtime.get()
  let assert Ok(_) = simplifile.create_directory_all("build/browser")
  let assert Ok(_) =
    simplifile.write(
      "build/browser/entry.mjs",
      "import { main } from '../dev/javascript/phoenix_counters_browser/phoenix_counters_browser.mjs';\nmain();\n",
    )
  let options =
    json.object([
      #("entrypoints", json.array(["build/browser/entry.mjs"], json.string)),
      #("target", json.string("browser")),
      #("format", json.string("iife")),
      #("minify", json.bool(True)),
    ])
    |> json.to_string
  use compiled <- promise.await(bundle.build(bun, options))
  let assert Ok(compiled) = compiled
  assert bundle.success(compiled) as string.join(bundle.logs(compiled), "\n")
  let assert [output] = bundle.outputs(compiled)
  use code <- promise.map(bundle.text(output))
  let assert Ok(_) = simplifile.create_directory_all("../priv/static/assets/js")
  let assert Ok(_) = simplifile.write("../priv/static/assets/js/app.js", code)
  io.println("Bundled Gleam Phoenix hooks and editor")
}
