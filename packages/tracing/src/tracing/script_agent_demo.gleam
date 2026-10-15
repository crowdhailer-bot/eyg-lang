//// Check and record the script agent guide against a real local HTTP fixture.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/run
import glasshouse/session
import glasshouse/value
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_demo as terminal
import tracing/terminal_fixture

const recording = "packages/tracing/recordings/script-agent.mp4"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let directory = filepath.join(cwd, ".recordings/script-agent")
  case simplifile.exists(directory, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(directory)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let binary =
    dict.from_list(env)
    |> dict.get("EYG_BIN")
    |> result.unwrap(filepath.join(root, "packages/gleam_cli/dist/eyg"))
  let assert Ok(fixture) =
    terminal_fixture.start_with(
      "let _ = perform StandardOut(\"Hello from the script agent\\n\") context.twice(21)",
      "Doubled 21 to 42 using the script context.",
    )
  let checked =
    terminal.in_desktop(bun, root, env, fn() {
      use _ <- promise.await(timers.sleep(700))
      terminal.in_terminal(bun, root, env, fn() {
        let video = terminal.video(bun, root, env, recording)
        let checked =
          {
            use _ <- promise.await(terminal.submit(
              root,
              "LANGFUSE_PUBLIC_KEY='' LANGFUSE_SECRET_KEY='' EYG_AGENT_MODEL_ORIGIN='http://127.0.0.1:7206' EYG_AGENT_MODEL='fixture' EYG_TRACE_DIR="
                <> quote(directory)
                <> " "
                <> quote(binary)
                <> " script examples/overlay_script/entry.eyg",
            ))
            use _ <- promise.await(terminal.wait_for(root, "Type: Integer", 100))
            use _ <- promise.await(terminal.wait_for(root, ">>>", 100))
            use _ <- promise.await(timers.sleep(1400))
            use _ <- promise.await(terminal.submit(
              root,
              "Use the script context to double 21.",
            ))
            use _ <- promise.await(terminal.wait_for(
              root,
              "Doubled 21 to 42",
              200,
            ))
            use _ <- promise.await(timers.sleep(2000))
            use _ <- promise.await(terminal.key(root, "Enter"))
            use _ <- promise.await(terminal.wait_for(
              root,
              "Script resumed after the agent.",
              100,
            ))
            use _ <- promise.await(terminal.wait_shell(root, 100))
            use _ <- promise.await(timers.sleep(1500))
            use pane <- promise.map(terminal.capture(root))
            assert !string.contains(pane, "error:") as pane
            let assert Ok(_) =
              simplifile.write("recordings/script-agent.txt", pane)
            Nil
          }
          |> promise.map(Ok)
          |> promise.rescue(Error)
        use checked <- promise.await(checked)
        use _ <- promise.map(terminal.finish_video(video, root, recording))
        let assert Ok(_) = checked
        Nil
      })
    })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = checked
  let assert Ok([file]) = simplifile.read_directory(directory)
  let assert Ok(text) = simplifile.read(filepath.join(directory, file))
  let assert Ok(saved) = archive.from_string(text)
  assert archive.missing(saved) == []
  assert list.length(session.generations(saved.session)) == 2
  assert list.any(saved.session.events, fn(event) {
    case event {
      session.Execution(run.Run(
        kind: run.Tool(_),
        outcome: run.Returned(result),
        ..,
      )) -> value.render(result, saved.store) == "42"
      _ -> False
    }
  })
  assert list.all(rerun.session(saved.session, saved.store), fn(report) {
    report.problem == None
  })
  let assert Ok(_) = simplifile.write("recordings/script-agent.json", text)
  io.println(
    "PASS script type check, captured context, caller resumption, archive and offline replay",
  )
}

fn quote(text) {
  "'" <> string.replace(text, "'", "'\\''") <> "'"
}
