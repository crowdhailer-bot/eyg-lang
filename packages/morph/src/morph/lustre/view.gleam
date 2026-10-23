//// Draw a Morph projection with Lustre.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import morph/frame

pub fn element(node: frame.Node) -> Element(a) {
  case node {
    frame.Text(text) -> element.text(text)
    frame.Span(attributes, children) ->
      h.span(list.map(attributes, attribute), list.map(children, element))
    frame.Div(attributes, children) ->
      h.div(list.map(attributes, attribute), list.map(children, element))
  }
}

fn attribute(attribute) {
  case attribute {
    frame.Class(class) -> a.class(class)
    // Clicks on the web read the path from this attribute, innermost first.
    frame.Path(path) ->
      a.attribute(
        "data-rev",
        list.reverse(path) |> list.map(int.to_string) |> string.join(","),
      )
    frame.Title(title) -> a.title(title)
    frame.Indent -> a.styles([#("padding-left", "2ch")])
    frame.Focus ->
      a.styles([
        #("padding", ".25rem"),
        #("background-color", "rgb(167, 243, 208)"),
        #("border-radius", ".25rem"),
        #("margin", "-.25rem"),
      ])
    frame.Problem -> a.styles([#("text-decoration", "underline red wavy")])
  }
}
