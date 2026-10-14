//// Install a Gleam project's compiled modules for a native Mix compiler hook.

import argv
import filepath
import gleam/io
import gleam/list
import gleam/string
import shellout
import simplifile

pub fn main() {
  let assert [destination] = argv.load().arguments
  // Running a dependency's main builds that dependency, not the caller's
  // project. Build the embedding application's modules before copying them.
  let assert Ok(output) =
    shellout.command(
      "gleam",
      ["build", "--target", "erlang", "--warnings-as-errors"],
      ".",
      [],
    )
  io.print(output)
  let assert Ok(_) = simplifile.create_directory_all(destination)
  let assert Ok(files) = simplifile.get_files("build/dev/erlang")
  let modules = list.filter(files, fn(path) { string.ends_with(path, ".beam") })
  list.each(modules, fn(path) {
    let target = filepath.join(destination, filepath.base_name(path))
    let assert Ok(_) = simplifile.copy_file(path, target)
    Nil
  })
  io.println(
    "Installed " <> string.inspect(list.length(modules)) <> " BEAM modules",
  )
}
