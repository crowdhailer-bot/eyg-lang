//// `eyg tui` on the BEAM. The shell runs in the same process as the screen;
//// effects that need the JavaScript runtime, such as network requests, are
//// unavailable.

import argv
import eyg/cli/args
import eyg/cli/tui
import gleam/io

pub fn main() {
  case args.parse(["tui", ..argv.load().arguments]) {
    args.Tui(input) -> tui.run(input)
    _ -> io.println_error("usage: gleam run [<file>]")
  }
}
