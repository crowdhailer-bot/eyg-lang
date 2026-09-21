//// Bundle the playground into `dist`, `jev_playground_dev` serves it.
//// `gleam run -m jev_playground_build --runtime bun`

import filepath
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/asset/server
import mysig/html
import simplifile
import snag

pub fn main() {
  use result <- promise.map(server.build_manifest(page(), dict.new()))
  let written = {
    use #(html, assets) <- result.try(result.map_error(
      result,
      snag.pretty_print,
    ))
    let files = [
      #("index.html", <<html:utf8>>),
      ..list.map(dict.to_list(assets), fn(asset) {
        let #(name, #(_file, _mime, bits)) = asset
        #("assets/" <> name, bits)
      })
    ]
    let _ = simplifile.delete("dist")
    list.try_each(files, fn(file) {
      let #(path, bits) = file
      let path = filepath.join("dist", path)
      use Nil <- result.try(
        simplifile.create_directory_all(filepath.directory_name(path)),
      )
      simplifile.write_bits(path, bits)
    })
    |> result.map_error(simplifile.describe_error)
  }
  case written {
    Ok(Nil) -> io.println("built dist")
    Error(reason) -> io.println(reason)
  }
}

pub fn page() {
  use script <- asset.do(asset.bundle("jev_playground/web", "client"))
  use style <- asset.do(asset.load("assets/app.css"))
  html.doc(
    [
      h.title([], "Jev playground"),
      html.stylesheet(asset.src(style)),
    ],
    [
      h.div([a.id("app")], []),
      h.script([a.src(asset.src(script))], ""),
    ],
  )
  |> element.to_document_string
  |> asset.done
}
