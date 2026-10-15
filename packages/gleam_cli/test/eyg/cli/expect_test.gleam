import eyg/ir/tree
import eyg/parser
import gleam/list
import gleam/string
import loam/platform/computer
import simplifile

fn handled_labels(node) {
  let children = tree.children(node) |> list.flat_map(handled_labels)
  case node.0 {
    tree.Handle(label) -> [label, ..children]
    _ -> children
  }
}

pub fn aok_mocks_the_complete_computer_harness_test() {
  let assert Ok(code) = simplifile.read("../../eyg_packages/aok/expect.eyg")
  let assert Ok(ast) = parser.all_from_string(code)
  let actual =
    handled_labels(ast)
    |> list.filter(fn(label) { label != "AokNext" })
    |> list.sort(string.compare)
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  // Use the CLI's local touch_grass dependency, rather than a published copy.
  // Every subject operation must have an adapter. Callback effects deliberately
  // use the surrounding runtime rather than a second interception boundary.
  let expected = labels |> list.sort(string.compare)
  assert actual == expected
}
