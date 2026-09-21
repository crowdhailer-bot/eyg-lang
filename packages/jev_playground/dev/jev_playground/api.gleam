//// Print the API of a library as Jev sees it.
//// `gleam run -m jev_playground/api --runtime bun -- standard`

import argv
import gleam/io
import gleam/list
import jev_playground/environment
import jev_playground/packages

pub fn main() {
  let assert [name] = argv.load().arguments
  let assert Ok(environment) = packages.environment()
  let assert Ok(library) = environment.find_library(environment, name)
  list.each(environment.library_api(library), fn(field) {
    io.println(field.0 <> ": " <> field.1)
  })
}
