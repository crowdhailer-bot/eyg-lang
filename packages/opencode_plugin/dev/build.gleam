//// Standalone policy runtime, built without a host application's source tree.

import gleam/io
import gleam/javascript/promise
import gleam/json
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(_) = simplifile.create_directory_all("dist")
  let options =
    json.object([
      #(
        "entrypoints",
        json.array(
          ["build/dev/javascript/opencode_plugin/core.mjs"],
          json.string,
        ),
      ),
      #("outdir", json.string("dist")),
      #("naming", json.object([#("entry", json.string("[name].mjs"))])),
      #("format", json.string("esm")),
      #("target", json.string("node")),
    ])
    |> json.to_string
  use built <- promise.map(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built)
    as "Unable to build the standalone policy runtime"
  io.println("Built dist/core.mjs")
}
