//// Record the patched pinned upstream OpenCode dispatcher check.

import filepath
import gleam/io
import gleam/javascript/promise
import gleam/string
import plinthx/bun/runtime
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/opencode-dispatcher.mp4"

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
            "cd packages/opencode_plugin && gleam run -m upstream_check",
          ))
          use _ <- promise.await(terminal.wait_for(
            root,
            "PASS actual OpenCode v1.19.0 dispatcher",
            100,
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(2500))
          use pane <- promise.map(terminal.capture(root))
          assert string.contains(pane, "PASS MCP tools") as pane
          assert string.contains(pane, "PASS Task metadata") as pane
          assert !string.contains(pane, "panic") as pane
          let assert Ok(_) =
            simplifile.write(
              "recordings/opencode-dispatcher.txt",
              string.trim_end(pane) <> "\n",
            )
          Nil
        }
        |> promise.map(Ok)
        |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println("PASS OpenCode dispatcher guide recording")
    })
  })
}
