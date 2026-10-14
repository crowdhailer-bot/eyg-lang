//// Record the native Erlang console against the real Gleam embedding runtime.

import filepath
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/string
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/package_fixture
import tracing/terminal_demo as terminal

const recording = "examples/erl_counter/video/erlang-counters.mp4"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let assert Ok(_) =
    simplifile.create_directory_all(filepath.join(
      root,
      "examples/erl_counter/video",
    ))
  let assert Ok(fixture) = package_fixture.start()
  let outcome =
    terminal.in_desktop(bun, root, env, fn() {
      use _ <- promise.await(timers.sleep(700))
      terminal.in_terminal(bun, root, env, fn() {
        walkthrough(bun, root, env, fixture)
      })
    })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.map(server.stop(fixture.server, True))
  case outcome {
    Ok(_) ->
      io.println(
        "PASS Erlang effects, package cache reuse and checked recording",
      )
    Error(error) -> panic as string.inspect(error)
  }
}

fn walkthrough(bun, root, env, fixture: package_fixture.Fixture) {
  use _ <- promise.await(terminal.submit(
    root,
    "erl -sname eyg_roadmap_counters -pa examples/erl_counter/build/dev/erlang/*/ebin",
  ))
  use _ <- promise.await(terminal.wait_for(root, "Eshell", 100))
  let video = terminal.video(bun, root, env, recording)
  let outcome =
    {
      use _ <- promise.await(terminal.submit(
        root,
        "application:set_env(erl_counter, hub, <<\"http://127.0.0.1:7207\">>), {ok, _} = application:ensure_all_started(erl_counter), ok.",
      ))
      use _ <- promise.await(terminal.submit(
        root,
        "{ok, S} = counters_session:start_link(), ok.",
      ))
      use _ <- promise.await(terminal.submit(
        root,
        "Ref = \"" <> fixture.reference <> "\", ok.",
      ))
      use _ <- promise.await(terminal.submit(
        root,
        "{ok, Type} = counters_session:check(S, Ref ++ \".list.map([1, 2], (n) -> { n })\"), io:format(\"~ts~n\", [Type]).",
      ))
      use _ <- promise.await(wait_line(root, "List(Integer)", 100))
      assert fixture.count() == 3
      use _ <- promise.await(timers.sleep(900))
      use _ <- promise.await(terminal.submit(
        root,
        "counters_session:cached(S, {package, <<\"standard\">>}).",
      ))
      use _ <- promise.await(wait_line(root, "true", 100))
      use _ <- promise.await(terminal.submit(
        root,
        "{ok, _} = counters_session:run(S, Ref ++ \".list.map([\\\"a\\\", \\\"b\\\"], (name) -> { perform StartCounter(name) })\"), io:format(\"Counters started.~n\").",
      ))
      use _ <- promise.await(wait_line(root, "Counters started.", 100))
      assert fixture.count() == 3
      use _ <- promise.await(terminal.submit(
        root,
        "_ = counters_eyg:run(\"perform GetValue(\\\"a\\\")\"), ok.",
      ))
      use _ <- promise.await(wait_line(root, "Ok(0)", 100))
      use _ <- promise.await(timers.sleep(900))
      use _ <- promise.await(terminal.submit(
        root,
        "_ = counters_eyg:run(\"perform SetTickRate({name: \\\"a\\\", seconds: 1})\"), ok.",
      ))
      use _ <- promise.await(wait_line(root, "Ok({})", 100))
      use _ <- promise.await(timers.sleep(1400))
      use _ <- promise.await(terminal.submit(
        root,
        "_ = counters_eyg:run(\"perform GetValue(\\\"a\\\")\"), ok.",
      ))
      use _ <- promise.await(wait_positive(root, 100))
      use _ <- promise.await(terminal.submit(
        root,
        "_ = counters_eyg:run(\"let _ = perform StartCounter(\\\"blocked\\\") perform GetValue(3)\"), ok.",
      ))
      use _ <- promise.await(terminal.wait_for(
        root,
        "type mismatch given: Integer expected: String",
        100,
      ))
      use _ <- promise.await(timers.sleep(1200))
      use _ <- promise.await(terminal.submit(
        root,
        "counters_api:get_value(<<\"blocked\">>).",
      ))
      use _ <- promise.await(wait_line(root, "{error,not_found}", 100))
      use _ <- promise.await(terminal.submit(
        root,
        "_ = counters_session:run(S, \"let _ = perform Shutdown(\\\"a\\\") perform Shutdown(\\\"b\\\")\"), gen_server:stop(S), ok.",
      ))
      use _ <- promise.await(timers.sleep(900))
      use pane <- promise.map(terminal.capture(root))
      assert !string.contains(pane, "exception error")
      assert fixture.count() == 3
      let assert Ok(_) =
        simplifile.write(
          filepath.join(root, "examples/erl_counter/video/session.txt"),
          pane,
        )
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.await(terminal.finish_video(video, root, recording))
  use _ <- promise.await(terminal.submit(root, "init:stop()."))
  use _ <- promise.map(terminal.wait_shell(root, 100))
  let assert Ok(_) = outcome
  Nil
}

fn wait_line(root, expected, attempts) {
  wait(root, fn(line) { line == expected }, attempts)
}

fn wait_positive(root, attempts) {
  wait(
    root,
    fn(line) {
      case line {
        "Ok(" <> value ->
          case int.parse(string.drop_end(value, 1)) {
            Ok(value) if value >= 1 -> True
            _ -> False
          }
        _ -> False
      }
    },
    attempts,
  )
}

fn wait(root, matches, attempts) {
  use pane <- promise.await(terminal.capture(root))
  case
    list.any(string.split(pane, "\n"), fn(line) { matches(string.trim(line)) }),
    attempts
  {
    True, _ -> promise.resolve(Nil)
    False, 0 -> panic as { "Expected console output missing: " <> pane }
    False, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait(root, matches, attempts - 1)
    }
  }
}
