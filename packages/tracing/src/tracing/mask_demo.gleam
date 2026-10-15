//// Check and record the guide's mask expression and pure application.

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

const recording = "packages/tracing/recordings/masking-effects.mp4"

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
  let assert Ok(guide) =
    simplifile.read(filepath.join(root, "guides/masking_effects.md"))
  let assert Ok(#(_, code)) = string.split_once(guide, "```eyg\n")
  let assert Ok(#(code, _)) = string.split_once(code, "```")
  let code = string.replace(string.trim(code), "\n", " ")
  terminal.in_desktop(bun, root, env, fn() {
    use _ <- promise.await(timers.sleep(700))
    terminal.in_terminal(bun, root, env, fn() {
      let video = terminal.video(bun, root, env, recording)
      let checked =
        {
          use _ <- promise.await(terminal.submit(
            root,
            quote(binary) <> " eval -c " <> quote(code),
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(1700))
          use _ <- promise.await(terminal.submit(
            root,
            quote(binary)
              <> " eval -c "
              <> quote("!pure((x) -> { !int_add(x, 1) })(41)"),
          ))
          use _ <- promise.await(terminal.wait_shell(root, 100))
          use _ <- promise.await(timers.sleep(1700))
          use pane <- promise.map(terminal.capture(root))
          let lines = string.split(pane, "\n") |> list.map(string.trim)
          assert list.contains(lines, "101") as pane
          assert list.contains(lines, "42") as pane
          assert !string.contains(pane, "error:") as pane
          let assert Ok(_) =
            simplifile.write(
              "recordings/masking-effects.txt",
              string.trim_end(pane) <> "\n",
            )
          Nil
        }
        |> promise.map(Ok)
        |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println("PASS mask routing and pure application from the guide")
    })
  })
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
