//// Real SIGINT, resumed CLI input and the saved interrupted trajectory.

import filepath
import glasshouse/archive
import glasshouse/session
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import javascript/mutable_reference as cell
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal

const recording = "packages/tracing/recordings/cli-interrupt.mp4"

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
  let directory = filepath.join(cwd, ".recordings/cli-interrupt")
  case simplifile.exists(directory, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(directory)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let requests = cell.new([])
  let assert Ok(fixture) = start(requests)
  let checked =
    terminal.in_desktop(bun, root, env, fn() {
      use _ <- promise.await(timers.sleep(700))
      terminal.in_terminal(bun, root, env, fn() {
        let launch =
          "EYG_TRACE_DIR="
          <> quote(directory)
          <> " "
          <> quote(binary)
          <> " overlay packages/tracing/fixtures/cli-interrupt.eyg"
        use _ <- promise.await(terminal.submit(root, launch))
        use _ <- promise.await(terminal.wait_for(root, ">>>", 100))
        let video = terminal.video(bun, root, env, recording)
        let checked =
          {
            use _ <- promise.await(terminal.submit(root, "pause"))
            use _ <- promise.await(wait_request(requests, 100))
            use _ <- promise.await(terminal.key(root, "C-c"))
            use _ <- promise.await(terminal.wait_for(
              root,
              "Stopped, send a message to continue.",
              100,
            ))
            use _ <- promise.await(timers.sleep(1000))
            use _ <- promise.await(terminal.submit(root, "resume"))
            use _ <- promise.await(terminal.wait_for(
              root,
              "Resumed normally.",
              100,
            ))
            use _ <- promise.await(timers.sleep(1200))
            use pane <- promise.await(terminal.capture(root))
            assert !string.contains(pane, ">>> pausea message")
              && !string.contains(pane, ">>> resume message")
              as pane
            let assert Ok(_) =
              simplifile.write(
                "recordings/cli-interrupt.txt",
                string.trim_end(pane) <> "\n",
              )
            use _ <- promise.await(terminal.key(root, "C-c"))
            use _ <- promise.await(terminal.wait_shell(root, 100))
            let assert Ok(files) = simplifile.read_directory(directory)
            let assert [file] = files
            let assert Ok(text) =
              simplifile.read(filepath.join(directory, file))
            let assert Ok(saved) = archive.from_string(text)
            assert archive.missing(saved) == []
            let assert [stopped, continued] = session.generations(saved.session)
            assert stopped.error == Some("Stopped, send a message to continue.")
            assert continued.content == "Resumed normally."
            assert continued.error != stopped.error
            assert list.length(cell.get(requests)) == 2
            let assert Ok(_) =
              simplifile.write("recordings/cli-interrupt.json", text)
            promise.resolve(Nil)
          }
          |> promise.map(Ok)
          |> promise.rescue(Error)
        use checked <- promise.await(checked)
        use _ <- promise.map(terminal.finish_video(video, root, recording))
        let assert Ok(_) = checked
      })
    })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use stopped <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = checked
  io.println(
    "PASS real Ctrl-C stops a turn, resumes input and saves its closed trajectory",
  )
}

fn start(requests) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7208, "127.0.0.1", fn(request) {
      use body <- promise.await(fetch.request_text(request))
      let assert Ok(body) = body
      let _ = cell.update(requests, fn(previous) { [body, ..previous] })
      let message = decode.field("content", decode.string, decode.success)
      let assert Ok(messages) =
        json.parse(
          body,
          decode.field("messages", decode.list(message), decode.success),
        )
      let pause = list.contains(messages, "pause")
      use _ <- promise.map(
        timers.sleep(case pause {
          True -> 2000
          False -> 50
        }),
      )
      let json =
        json.object([
          #(
            "message",
            json.object([
              #("role", json.string("assistant")),
              #(
                "content",
                json.string(case pause {
                  True -> "Interrupted response."
                  False -> "Resumed normally."
                }),
              ),
              #("tool_calls", json.array([], json.string)),
            ]),
          ),
          #("done", json.bool(True)),
          #("prompt_eval_count", json.int(4)),
          #("eval_count", json.int(3)),
        ])
        |> json.to_string
      let assert Ok(response) =
        fetch.new_response(constructor, json <> "\n", 200, [
          #("content-type", "application/x-ndjson"),
        ])
      response
    }),
  )
}

fn wait_request(requests, attempts) {
  case cell.get(requests), attempts {
    [_, ..], _ -> promise.resolve(Nil)
    [], 0 -> panic as "The CLI did not start its model request"
    [], _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_request(requests, attempts - 1)
    }
  }
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
