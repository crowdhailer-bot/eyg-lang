//// Execute and record the retained-shell example from the embedding guide.

import filepath
import gleam/io
import gleam/javascript/promise
import gleam/string
import plinthx/bun/runtime
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/embedding-shell.mp4"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  terminal.in_desktop(bun, root, env, fn() {
    use _ <- promise.await(timers.sleep(700))
    terminal.in_terminal(bun, root, env, fn() {
      let video = terminal.video(bun, root, env, recording)
      let checked =
        {
          use _ <- promise.await(terminal.submit(
            root,
            "cd packages/gleam_embed && gleam run --runtime node -m host_shell",
          ))
          use _ <- promise.await(terminal.wait_for(
            root,
            "PASS retained bindings",
            100,
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(2500))
          use pane <- promise.map(terminal.capture(root))
          assert string.contains(pane, "nothing ran") as pane
          assert string.contains(pane, "still here") as pane
          assert !string.contains(pane, "panic") as pane
          let assert Ok(_) =
            simplifile.write(
              "recordings/embedding-shell.txt",
              string.trim_end(pane) <> "\n",
            )
          Nil
        }
        |> promise.map(Ok)
        |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println("PASS retained-shell guide recording")
    })
  })
}
