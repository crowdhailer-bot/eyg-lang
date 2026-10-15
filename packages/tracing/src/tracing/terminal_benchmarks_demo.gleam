//// Record a complete report validation after the measurement processes stop.

import filepath
import gleam/io
import gleam/javascript/promise
import gleam/string
import plinthx/bun/runtime
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/terminal-benchmarks.mp4"

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
            "cd packages/overlay_tui_bench && gleam run -- report",
          ))
          use _ <- promise.await(terminal.wait_for(
            root,
            "PASS 60 fresh trials and 80 historical trials",
            100,
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(2500))
          use pane <- promise.map(terminal.capture(root))
          assert string.contains(pane, "core") as pane
          assert string.contains(pane, "lustre") as pane
          assert string.contains(pane, "signals") as pane
          assert !string.contains(pane, "panic") as pane
          let assert Ok(_) =
            simplifile.write(
              "recordings/terminal-benchmarks.txt",
              string.trim_end(pane) <> "\n",
            )
          Nil
        }
        |> promise.map(Ok)
        |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println("PASS terminal benchmark guide recording")
    })
  })
}
