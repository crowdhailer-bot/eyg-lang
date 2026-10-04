import gleam/javascript/promise
import gleam/list
import gleam/string
import gleam_opentui as o
import gleam_opentui/testing as t
import gleeunit
import gleeunit/should

pub fn retained_objects_mutate_through_their_native_receiver_test() {
  use setup <- promise.await(t.create("{\"width\":40,\"height\":8}"))
  let setup = setup |> should.be_ok
  let renderer = t.renderer(setup)
  let parent =
    o.new_box(renderer, "{\"width\":40,\"height\":8}") |> should.be_ok
  o.add(o.root(renderer), parent) |> should.be_ok
  let node = o.new_text(renderer, "{\"content\":\"before\"}") |> should.be_ok
  o.add(parent, node) |> should.be_ok
  let same = o.children(parent) |> list.first |> should.be_ok
  same |> should.equal(o.as_base(node))
  o.set_text_content(node, "after 🌱") |> should.be_ok
  use rendered <- promise.map(t.render_once(setup))
  should.be_ok(rendered)
  let frame = t.capture(setup)
  o.remove(parent, node) |> should.be_ok
  o.children(parent) |> should.equal([])
  o.destroy_node(node) |> should.be_ok
  o.destroy_renderer(renderer) |> should.be_ok
  frame |> string.contains("after 🌱") |> should.be_true
}

pub fn invalid_options_and_destroyed_styles_return_results_test() {
  use invalid <- promise.map(t.create("invalid json"))
  should.be_error(invalid)
  let style =
    o.new_syntax_style("{\"number\":{\"fg\":\"#ffffff\"}}") |> should.be_ok
  o.style_id(style, "number") |> should.be_ok |> should.be_ok
  o.style_id(style, "missing") |> should.equal(Ok(Error(Nil)))
  o.destroy_style(style) |> should.be_ok
  o.style_id(style, "number") |> should.be_error
}

pub fn main() {
  gleeunit.main()
}
