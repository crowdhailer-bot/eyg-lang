import gleam/list
import gleam/string
import lustre/element
import pamphlet
import pamphlet/lustre
import simplifile
import website/guide_highlight
import website/routes/glasshouse
import website/routes/glasshouse/documentation

pub fn every_page_builds_test() {
  glasshouse.route()
}

pub fn contents_link_to_every_heading_test() {
  let assert Ok(text) =
    simplifile.read("src/website/routes/glasshouse/documentation.md")
  let #(_, document) = pamphlet.parse(text)
  let html =
    lustre.to_lustre(document, guide_highlight.renderer())(fn(x) { x })
    |> element.to_string
  let headings =
    string.split(text, "\n")
    |> list.filter_map(fn(line) {
      case line {
        "## " <> title | "### " <> title -> Ok(title)
        _ -> Error(Nil)
      }
    })
  let assert [_, ..] = headings
  assert list.all(headings, fn(title) {
    string.contains(html, "id=\"" <> documentation.heading_id(title) <> "\"")
  })
}
