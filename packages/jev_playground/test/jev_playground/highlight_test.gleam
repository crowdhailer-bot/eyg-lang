import gleam/list
import gleam/regexp
import gleam/string
import jev_playground/highlight
import lustre/element

fn html(code) {
  highlight.highlight_program(code) |> element.fragment |> element.to_string
}

pub fn every_kind_of_token_is_classed_test() {
  let out =
    html("let x = @standard.list.length([1]) !equal(x, \"a\") Ok(?) todo")
  list.each(
    ["keyword", "package", "builtin", "string", "number", "tag", "hole"],
    fn(class) {
      assert string.contains(out, "class=\"" <> class <> "\"")
    },
  )
}

pub fn the_selection_is_marked_test() {
  let out = html("count(«records(\"a\")»)")
  assert string.contains(out, "class=\"selection\"")
  assert !string.contains(out, "«")
}

pub fn the_code_is_kept_as_written_test() {
  let code = "context.create_zone_record(\"a.dev\", {name: \"\", ttl: 3600})"
  let assert Ok(tags) = regexp.from_string("<[^>]*>")
  let written =
    html(code)
    |> regexp.replace(tags, _, "")
    |> string.replace("&quot;", "\"")
  assert written == code
}
