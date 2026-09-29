import eyg/ir/tree as ir

// A balanced tree has few levels but many nodes. Continuation passing grows
// the stack with every node on JavaScript, where there are no tail calls.
// Node and browsers overflow on this, bun has a larger stack and does not.
fn wide(depth) {
  case depth {
    0 -> ir.integer(1)
    _ -> ir.apply(wide(depth - 1), wide(depth - 1))
  }
}

pub fn a_wide_tree_can_be_annotated_test() {
  let source = wide(16)
  assert ir.map_annotation(source, fn(_) { 1 }) |> ir.clear_annotation == source
}

pub fn a_wide_tree_can_be_searched_for_references_and_builtins_test() {
  let source =
    ir.apply(wide(16), ir.apply(ir.builtin("int_add"), ir.package("standard")))
  assert ir.list_builtins(source) == ["int_add"]
  assert ir.list_references(source) == [ir.Package("standard")]
}
