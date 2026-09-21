//// Print the number of steps each demo takes and how many are compound moves.
//// `gleam run -m jev_playground/demos --runtime bun`

import gleam/int
import gleam/io
import gleam/list
import jev_playground/action
import jev_playground/demo
import jev_playground/library
import jev_playground/packages

pub fn main() {
  let assert Ok(bundle) = packages.bundle()
  list.each(demo.all(), fn(demo) {
    let assert Ok(environment) = library.environment(bundle, demo.environment)
    case demo.prepare(demo, environment) {
      Ok(demo.Prepared(actions:, ..)) -> {
        let compounds =
          list.filter_map(actions, fn(action) {
            case action {
              action.Compound(steps:, ..) -> Ok(list.length(steps))
              _ -> Error(Nil)
            }
          })
        io.println(
          demo.slug
          <> ": "
          <> int.to_string(list.length(actions))
          <> " choices, "
          <> int.to_string(list.length(compounds))
          <> " compound moves covering "
          <> int.to_string(int.sum(compounds))
          <> " edits",
        )
      }
      Error(reason) -> io.println(demo.slug <> ": " <> reason)
    }
  })
}
