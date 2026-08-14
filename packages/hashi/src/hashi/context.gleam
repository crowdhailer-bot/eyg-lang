//// Reading `eyg/context.eyg`.
////
//// The context is the workspace the agent and the shell share: a readme, which
//// is what the model is told, and the functions the readme describes, which
//// both of them start with in hand.
////
//// The module is pure. Its functions perform effects when they are called, but
//// building them does not, and it references no package and imports no file.
//// So it is read here and now, with no network and no waiting, which is what
//// lets a page whose harness has no `Fetch` have a library at all.

import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug
import gleam/dict
import gleam/result

pub type Meta =
  List(Int)

pub type Context {
  Context(
    /// What the model is told about the workspace.
    readme: String,
    /// Every field of the module, bound by name, ready to be the scope a
    /// program starts in.
    scope: List(#(String, istate.Value(Meta))),
  )
}

pub fn load(source: String) -> Result(Context, String) {
  use tree <- result.try(
    parser.all_from_string(source)
    |> result.map_error(debug.describe),
  )
  use value <- result.try(
    tree
    |> ir.map_annotation(fn(_) { [] })
    |> expression.execute([])
    |> result.map_error(fn(broken) {
      let #(reason, _, _, _) = broken
      simple_debug.describe(reason)
    }),
  )
  use fields <- result.try(case value {
    v.Record(fields) -> Ok(fields)
    _ -> Error("the context module is not a record")
  })
  use readme <- result.try(case dict.get(fields, "readme") {
    Ok(v.String(readme)) -> Ok(readme)
    Ok(_) -> Error("the context module's readme is not a string")
    Error(Nil) -> Error("the context module has no readme")
  })
  Ok(Context(readme:, scope: dict.to_list(fields)))
}
