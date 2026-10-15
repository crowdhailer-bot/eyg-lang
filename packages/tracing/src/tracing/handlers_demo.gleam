//// Execute and record the deep-handler guide's interpreter examples.

import filepath
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import plinthx/bun/runtime
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/deep-handlers.mp4"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let binary =
    dict.from_list(env)
    |> dict.get("EYG_BIN")
    |> result.unwrap(filepath.join(root, "packages/gleam_cli/dist/eyg"))
  terminal.in_desktop(bun, root, env, fn() {
    use _ <- promise.await(timers.sleep(700))
    terminal.in_terminal(bun, root, env, fn() {
      let video = terminal.video(bun, root, env, recording)
      let checked =
        {
          use _ <- promise.await(terminal.submit(
            root,
            quote(binary) <> " eval guides/examples/deep_handlers.eyg",
          ))
          use _ <- promise.await(terminal.wait_for(root, "forwarded: 200", 100))
          use _ <- promise.await(terminal.wait_for(root, "multi_shot: 6", 100))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(2000))
          use _ <- promise.await(terminal.submit(
            root,
            quote(binary) <> " eval guides/examples/stateful_handler.eyg",
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(2000))
          use pane <- promise.map(terminal.capture(root))
          assert list.any(string.split(pane, "\n"), fn(line) {
            string.trim(line) == "3"
          })
            as pane
          assert !string.contains(pane, "error:") as pane
          let assert Ok(_) =
            simplifile.write("recordings/deep-handlers.txt", pane)
          Nil
        }
        |> promise.map(Ok)
        |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println(
        "PASS deep scope, independent resumptions and state-passing guide",
      )
    })
  })
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
