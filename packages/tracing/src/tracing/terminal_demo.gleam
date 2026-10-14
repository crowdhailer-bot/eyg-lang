//// Record `eyg tui` with Xvfb, xterm, tmux and ffmpeg, orchestrated in Gleam.
//// Build packages/gleam_cli first.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/session
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import loam/system
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/terminal_fixture

const tmux_name = "eyg-roadmap-guide"

const display = ":97"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host)
  let assert Ok(model) = terminal_fixture.start()
  let outcome =
    in_desktop(bun, root, env, fn() { record_all(bun, root, env) })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.map(server.stop(model, True))
  case outcome {
    Ok(_) -> io.println("PASS checked real terminal recordings")
    Error(error) -> panic as failure(error)
  }
}

/// Shared capture lifecycle for the terminal walkthroughs.
pub fn in_desktop(bun, root, env, work) {
  let assert Ok(False) = simplifile.exists("/tmp/.X97-lock", follow_links: True)
  let xvfb =
    spawn(bun, root, env, [
      "Xvfb",
      display,
      "-screen",
      "0",
      "1400x900x24",
      "-nolisten",
      "tcp",
    ])
  let outcome = work() |> promise.map(Ok) |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  let _ = subprocess.kill(xvfb, "SIGTERM")
  use _ <- promise.map(subprocess.exited(xvfb))
  case outcome {
    Ok(_) -> Nil
    Error(error) -> panic as failure(error)
  }
}

fn record_all(bun, root, env) {
  use _ <- promise.await(timers.sleep(700))
  io.println("Recording eyg tui and Overlay")
  in_terminal(bun, root, env, fn() {
    use _ <- promise.await(submit(root, "cd packages/gleam_cli"))
    use _ <- promise.await(shell(bun, root, env))
    overlay(bun, root, env)
  })
}

pub fn in_terminal(bun, root, env, work) {
  use _ <- promise.await(
    command(root, "tmux", [
      "-L",
      "agent",
      "new-session",
      "-d",
      "-s",
      tmux_name,
      "-x",
      "110",
      "-y",
      "34",
      "-c",
      root,
    ]),
  )
  use _ <- promise.await(
    command(root, "tmux", [
      "-L",
      "agent",
      "set-option",
      "-t",
      tmux_name,
      "status",
      "off",
    ]),
  )
  let xterm =
    spawn(
      bun,
      root,
      dict.merge(dict.from_list(env), dict.from_list([#("DISPLAY", display)]))
        |> dict.to_list,
      [
        "xterm",
        "-geometry",
        "110x34+0+0",
        "-fa",
        "DejaVu Sans Mono",
        "-fs",
        "14",
        "-bg",
        "#141414",
        "-fg",
        "#eeeeee",
        "-b",
        "2",
        "-e",
        "tmux",
        "-L",
        "agent",
        "attach-session",
        "-t",
        tmux_name,
      ],
    )
  let outcome =
    {
      use _ <- promise.await(timers.sleep(500))
      work()
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.await(
    command(root, "tmux", ["-L", "agent", "kill-session", "-t", tmux_name]),
  )
  // This window belongs to the recorder. Terminate it even if its tmux client
  // switched to another existing session after the recorded session closed.
  let _ = subprocess.kill(xterm, "SIGKILL")
  use _ <- promise.map(subprocess.exited(xterm))
  case outcome {
    Ok(_) -> Nil
    Error(error) -> panic as failure(error)
  }
}

fn shell(bun, root, env) {
  io.println("Checking the shell")
  use _ <- promise.await(submit(root, "gleam run -- tui"))
  use _ <- promise.await(wait_for(root, "Ready", 100))
  let recording = video(bun, root, env, recordings <> "/terminal-repl.mp4")
  let outcome =
    {
      use _ <- promise.await(submit(root, "!int_add(20, 22)"))
      use _ <- promise.await(wait_for(root, "42", 100))
      use _ <- promise.await(timers.sleep(800))
      use _ <- promise.await(submit(root, "let answer = 40"))
      use _ <- promise.await(submit(root, "!int_add(answer, 2)"))
      use _ <- promise.await(timers.sleep(800))
      use _ <- promise.await(submit(
        root,
        "perform StandardOut(\"Hello from Gleam\")",
      ))
      use _ <- promise.await(wait_for(root, "▸ 1 effects", 100))
      use _ <- promise.await(key(root, "C-e"))
      use _ <- promise.await(wait_for(root, "↳ {}", 100))
      use _ <- promise.await(timers.sleep(1000))
      use _ <- promise.await(submit(root, "/type answer"))
      use _ <- promise.await(wait_for(root, "Integer", 100))
      use _ <- promise.await(timers.sleep(1000))
      use _ <- promise.await(type_text(root, "!int_add(20, 22)"))
      use _ <- promise.await(key(root, "F2"))
      use _ <- promise.await(timers.sleep(400))
      use _ <- promise.await(key(root, "Right"))
      use _ <- promise.await(timers.sleep(300))
      use _ <- promise.await(key(root, "Right"))
      use _ <- promise.await(timers.sleep(300))
      use _ <- promise.await(type_text(root, "n"))
      use _ <- promise.await(timers.sleep(300))
      use _ <- promise.await(type_text(root, "40"))
      use _ <- promise.await(key(root, "Enter"))
      use _ <- promise.await(timers.sleep(800))
      use _ <- promise.await(type_text(root, "z"))
      use _ <- promise.await(timers.sleep(600))
      use _ <- promise.await(type_text(root, "Z"))
      use _ <- promise.await(timers.sleep(600))
      use _ <- promise.await(key(root, "Enter"))
      use _ <- promise.await(timers.sleep(1200))
      use pane <- promise.map(capture(root))
      assert string.contains(pane, "62")
      assert string.contains(pane, "Integer")
      assert string.contains(pane, "StandardOut")
      let assert Ok(_) =
        simplifile.write(
          filepath.join(root, recordings <> "/terminal-repl.txt"),
          pane,
        )
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.await(finish_video(
    recording,
    root,
    recordings <> "/terminal-repl.mp4",
  ))
  use _ <- promise.await(key(root, "C-c"))
  use _ <- promise.map(wait_shell(root, 100))
  let assert Ok(_) = outcome
}

fn overlay(bun, root, env) {
  io.println("Checking Overlay")
  use _ <- promise.await(submit(
    root,
    "gleam run -- tui overlay ../tracing/fixtures/tui/local.eyg",
  ))
  use _ <- promise.await(wait_for(root, "Ready", 100))
  let recording = video(bun, root, env, recordings <> "/terminal-overlay.mp4")
  let outcome =
    {
      use _ <- promise.await(timers.sleep(700))
      use _ <- promise.await(submit(
        root,
        "Print a greeting and calculate 20 plus 22.",
      ))
      use _ <- promise.await(wait_for(root, "trace saved", 150))
      use _ <- promise.await(timers.sleep(1500))
      check_archive(root)
      use _ <- promise.await(key(root, "C-o"))
      use _ <- promise.await(timers.sleep(1500))
      use _ <- promise.await(key(root, "C-e"))
      use _ <- promise.await(timers.sleep(1800))
      use pane <- promise.map(capture(root))
      assert string.contains(pane, "StandardOut")
      assert string.contains(pane, "passed")
      assert string.contains(pane, "42")
      let assert Ok(_) =
        simplifile.write(
          filepath.join(root, recordings <> "/terminal-overlay.txt"),
          pane,
        )
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.await(finish_video(
    recording,
    root,
    recordings <> "/terminal-overlay.mp4",
  ))
  use _ <- promise.await(key(root, "C-c"))
  use _ <- promise.map(wait_shell(root, 100))
  let assert Ok(_) = outcome
}

/// The trajectory saved by the turn, the newest in the CLI's traces.
fn check_archive(root) {
  let traces = filepath.join(root, "packages/gleam_cli/.eyg/traces")
  let assert Ok(names) = simplifile.read_directory(traces)
  let assert Ok(name) = list.sort(names, string.compare) |> list.last
  let assert Ok(text) = simplifile.read(filepath.join(traces, name))
  let assert Ok(trace) = archive.from_string(text)
  assert archive.missing(trace) == []
  assert list.length(session.generations(trace.session)) == 2
  assert session.usage(trace.session)
    == #(session.Usage(40, 20), session.Usage(0, 0))
  assert list.all(rerun.session(trace.session, trace.store), fn(report) {
    report.problem == None
  })
  let assert Ok(_) =
    simplifile.write(
      filepath.join(root, recordings <> "/terminal-trajectory.json"),
      text,
    )
  Nil
}

const recordings = "packages/tracing/recordings"

pub fn finish_video(child, root, path) {
  let _ = subprocess.kill(child, "SIGINT")
  use exit <- promise.await(subprocess.exited(child))
  case exit {
    Ok(0) | Ok(255) -> Nil
    _ -> panic as { "ffmpeg failed: " <> string.inspect(exit) }
  }
  use duration <- promise.map(
    command(root, "ffprobe", [
      "-v", "error", "-show_entries", "format=duration", "-of",
      "default=noprint_wrappers=1:nokey=1", path,
    ]),
  )
  assert string.trim(duration) != ""
}

pub fn video(bun, root, env, path) {
  spawn(bun, root, env, [
    "ffmpeg",
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "x11grab",
    "-draw_mouse",
    "0",
    "-framerate",
    "20",
    "-video_size",
    "1324x820",
    "-i",
    display <> "+0,0",
    "-c:v",
    "libx264",
    "-threads",
    "2",
    "-preset",
    "veryfast",
    "-crf",
    "22",
    "-pix_fmt",
    "yuv420p",
    "-movflags",
    "+faststart",
    "-y",
    path,
  ])
}

fn spawn(bun, root, env, command) {
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        cmd: command,
        cwd: root,
        env:,
        stdin: "ignore",
        stdout: "ignore",
        stderr: "inherit",
      ),
    )
  child
}

pub fn command(root, program, arguments) {
  use result <- promise.map(
    system.run(system.command(program, arguments, root)),
  )
  let assert Ok(result) = result
  result
}

pub fn key(root, key) {
  command(root, "tmux", ["-L", "agent", "send-keys", "-t", tmux_name, key])
}

pub fn type_text(root, text) {
  command(root, "tmux", [
    "-L",
    "agent",
    "send-keys",
    "-t",
    tmux_name,
    "-l",
    text,
  ])
}

pub fn submit(root, text) {
  use _ <- promise.await(type_text(root, text))
  use _ <- promise.await(timers.sleep(300))
  key(root, "Enter")
}

pub fn capture(root) {
  command(root, "tmux", ["-L", "agent", "capture-pane", "-p", "-t", tmux_name])
}

pub fn wait_for(root, text, attempts) {
  use pane <- promise.await(capture(root))
  case string.contains(pane, text), attempts {
    True, _ -> promise.resolve(Nil)
    False, 0 -> panic as { "Terminal did not show " <> text <> ": " <> pane }
    False, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_for(root, text, attempts - 1)
    }
  }
}

pub fn wait_shell(root, attempts) {
  use program <- promise.await(
    command(root, "tmux", [
      "-L", "agent", "display-message", "-p", "-t", tmux_name,
      "#{pane_current_command}",
    ]),
  )
  case string.trim(program), attempts {
    "bash", _ -> timers.sleep(300)
    _, 0 -> panic as { "Terminal did not return to its shell: " <> program }
    _, _ -> {
      use _ <- promise.await(timers.sleep(100))
      wait_shell(root, attempts - 1)
    }
  }
}

fn failure(error) {
  decode.run(error, decode.field("stack", decode.string, decode.success))
  |> result.unwrap(string.inspect(error))
}
