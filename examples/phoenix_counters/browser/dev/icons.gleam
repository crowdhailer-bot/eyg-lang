//// Generate Heroicons CSS from dependency SVG data in Gleam.

import gleam/list
import gleam/string
import plinthx/browser/node
import simplifile

pub fn main() {
  let variants = [
    #("24/outline", "", "1.5rem"),
    #("24/solid", "-solid", "1.5rem"),
    #("20/solid", "-mini", "1.25rem"),
    #("16/solid", "-micro", "1rem"),
  ]
  let css =
    list.flat_map(variants, fn(variant) {
      let assert Ok(paths) =
        simplifile.get_files("../deps/heroicons/optimized/" <> variant.0)
      list.filter_map(paths, fn(path) {
        case string.ends_with(path, ".svg") {
          False -> Error(Nil)
          True -> {
            let assert Ok(source) = simplifile.read(path)
            let assert Ok(file) = path |> string.split("/") |> list.last
            let name = string.drop_end(file, 4)
            let content =
              source
              |> string.replace("\n", "")
              |> string.replace("\r", "")
              |> node.encode_uri
            Ok(
              ".hero-"
              <> name
              <> variant.1
              <> "{display:inline-block;vertical-align:middle;width:"
              <> variant.2
              <> ";height:"
              <> variant.2
              <> ";background-color:currentColor;mask-repeat:no-repeat;mask-image:url('data:image/svg+xml;utf8,"
              <> content
              <> "');-webkit-mask-image:url('data:image/svg+xml;utf8,"
              <> content
              <> "')}\n",
            )
          }
        }
      })
    })
    |> string.concat
  let assert Ok(_) = simplifile.write("../assets/css/heroicons.css", css)
  Nil
}
