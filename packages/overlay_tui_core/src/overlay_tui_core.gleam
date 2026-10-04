import core/controller
import core/native
import core/native_view
import eyg/cli/args
import eyg_cli
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam_opentui as opentui
import loam/system
import plinthx/node/process
import plinthx/node/tty

pub fn main() {
  launch(native_view.mount)
}

/// Every frontend uses the same argument parsing and noninteractive CLI.
pub fn launch(mount) {
  let assert Ok(host) = process.get()
  let arguments = process.argv(host) |> array.to_list |> list.drop(2)
  let command = args.parse(arguments)
  let interactive = case command {
    args.Shell(_) | args.Overlay(_) -> True
    _ -> False
  }
  let terminal =
    tty.is_tty(process.stdin(host)) |> result.unwrap(False)
    && { tty.is_tty(process.stdout(host)) |> result.unwrap(False) }
  case interactive && terminal {
    False -> system.run(eyg_cli.start(arguments))
    True -> {
      use renderer <- promise.map(opentui.create_renderer(
        "{\"exitOnCtrlC\":false,\"useMouse\":true,\"targetFps\":60}",
      ))
      let renderer = native.must(renderer)
      let overlay = case command {
        args.Overlay(_) -> True
        _ -> False
      }
      let _ =
        controller.start(
          renderer,
          arguments,
          overlay,
          process.cwd(host) |> native.must,
          [],
          mount,
        )
      Nil
    }
  }
}
