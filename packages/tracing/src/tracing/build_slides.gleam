//// Bundle the Gleam controller into the offline HTML source template.

import gleam/io
import gleam/javascript/promise
import gleam/string
import simplifile
import tracing/host

pub fn main() {
  let output = "build/eval-slides.js"
  use built <- promise.map(
    host.command(
      [
        "bun",
        "build",
        "build/dev/javascript/tracing/tracing/eval_slides.mjs",
        "--target=browser",
        "--format=esm",
        "--footer=main();",
        "--outfile",
        output,
      ],
      ".",
      [],
    ),
  )
  let assert Ok(built) = built
  assert built.status == 0 as built.stderr
  let assert Ok(script) = simplifile.read(output)
  let assert Ok(template) =
    simplifile.read("../../blog/effect-evals/slides.template.html")
  let html =
    string.join(
      string.split(template, "<!--CONTROLLER-->"),
      "<script type=\"module\">\n// Generated from tracing/eval_slides.gleam.\n"
        <> string.replace(script, "</script", "<\\/script")
        <> "\n</script>",
    )
  let assert Ok(_) =
    simplifile.write("../../blog/effect-evals/slides.html", html)
  io.println("Built offline eval slides from Gleam")
}
