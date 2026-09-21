//// Bundle the playground into `dist`, `jev_playground_dev` serves it.
//// `gleam run -m jev_playground_build --runtime bun`

import filepath
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import jev_playground/demo
import jev_playground/library
import jev_playground/packages
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
    use bundle <- result.try(packages.bundle())
    let libraries = json.to_string(library.to_json(bundle))
    // Demo scripts take a while to find so they are found once here.
    use demos <- result.try(
      list.try_map(demo.all(), fn(demo) {
        use environment <- result.try(library.environment(
          bundle,
          demo.environment,
        ))
        use prepared <- result.map(demo.prepare(demo, environment))
        #(demo.slug, demo.prepared_to_json(prepared))
      }),
    )
    let demos = json.to_string(json.object(demos))
    let files = [
      #("index.html", <<html:utf8>>),
      #("libraries.json", <<libraries:utf8>>),
      #("demos.json", <<demos:utf8>>),
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
