//// Record and check the CLI's native prompt editor, using the shared desktop.

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

const recording = "packages/tracing/recordings/cli-prompts.mp4"

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
      use _ <- promise.await(terminal.submit(
        root,
        "'" <> string.replace(binary, "'", "'\\''") <> "'",
      ))
      use _ <- promise.await(terminal.wait_for(
        root,
        "type /help for shell commands",
        100,
      ))
      let video = terminal.video(bun, root, env, recording)
      let checked =
        walkthrough(root) |> promise.map(Ok) |> promise.rescue(Error)
      use checked <- promise.await(checked)
      use _ <- promise.map(terminal.finish_video(video, root, recording))
      let assert Ok(_) = checked
      io.println(
        "PASS live CLI editing, Unicode, history and checked recording",
      )
    })
  })
}

fn walkthrough(root) {
  use _ <- promise.await(terminal.type_text(root, "let answer = 43"))
  use _ <- promise.await(terminal.key(root, "Left"))
  use _ <- promise.await(terminal.key(root, "DC"))
  use _ <- promise.await(terminal.type_text(root, "1"))
  use _ <- promise.await(timers.sleep(1400))
  use _ <- promise.await(terminal.key(root, "Enter"))
  use _ <- promise.await(wait_prompt(root, 100))
  use _ <- promise.await(terminal.submit(root, "answer"))
  use _ <- promise.await(wait_line(root, "41", 100))
  use _ <- promise.await(wait_prompt(root, 100))
  use _ <- promise.await(timers.sleep(1400))
  use _ <- promise.await(terminal.key(root, "Up"))
  use _ <- promise.await(timers.sleep(1400))
  use _ <- promise.await(terminal.key(root, "Enter"))
  use _ <- promise.await(wait_prompt(root, 100))
  use _ <- promise.await(terminal.type_text(root, "\"é🌱\""))
  use _ <- promise.await(terminal.key(root, "Left"))
  use _ <- promise.await(terminal.key(root, "BSpace"))
  use _ <- promise.await(terminal.type_text(root, "🌿"))
  use _ <- promise.await(terminal.key(root, "End"))
  use _ <- promise.await(timers.sleep(1400))
  use _ <- promise.await(terminal.key(root, "Enter"))
  use _ <- promise.await(wait_line(root, "\"é🌿\"", 100))
  use _ <- promise.await(terminal.type_text(root, "discard this draft"))
  use _ <- promise.await(terminal.key(root, "C-u"))
  use _ <- promise.await(terminal.submit(root, "/t answer"))
  use _ <- promise.await(wait_line(root, "Integer", 100))
  use _ <- promise.await(timers.sleep(1800))
  use pane <- promise.await(terminal.capture(root))
  assert list.length(
      list.filter(string.split(pane, "\n"), fn(line) {
        string.trim(line) == "41"
      }),
    )
    == 2
  assert !string.contains(pane, "error:") as pane
  let assert Ok(_) =
    simplifile.write(
      "recordings/cli-prompts.txt",
      string.trim_end(pane) <> "\n",
    )
  use _ <- promise.await(terminal.key(root, "Enter"))
  use _ <- promise.map(terminal.wait_shell(root, 100))
  Nil
}

fn wait_line(root, expected, attempts) {
  use text <- promise.await(terminal.capture(root))
  case
    list.any(string.split(text, "\n"), fn(line) {
      string.trim(line) == expected
    }),
    attempts
  {
    True, _ -> promise.resolve(Nil)
    False, 0 -> panic as "Expected CLI output did not appear"
    False, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_line(root, expected, attempts - 1)
    }
  }
}

fn wait_prompt(root, attempts) {
  use text <- promise.await(terminal.capture(root))
  let last =
    string.split(text, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })
    |> list.last
  case last == Ok(">"), attempts {
    True, _ -> promise.resolve(Nil)
    False, 0 -> panic as "The CLI prompt did not return"
    False, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_prompt(root, attempts - 1)
    }
  }
}
