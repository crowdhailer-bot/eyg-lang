//// Use `eyg tui` in tmux as a person would. Each step types keys, and each
//// check waits for text to appear on the screen. Every checked screen and an
//// asciinema cast of the session are kept as evidence.
////
//// Build the CLI first: `gleam build` in packages/gleam_cli. Then
//// `gleam run -m tracing/tui_check -- shell|overlay|beam` here. Packages come
//// from a local hub and Overlay replies from a scripted model. For `beam`,
//// export packages/eyg_tui first: `gleam export erlang-shipment`.

import argv
import filepath
import gleam/bool
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import plinthx/bun/server
import shellout
import simplifile
import tracing/package_fixture
import tracing/terminal_fixture

pub type Step {
  Type(String)
  Key(String)
  /// Wait until the screen shows the text.
  Check(name: String, shows: String)
  Resize(Int, Int)
  /// Click the first place the screen shows this text.
  Click(String)
}

const session = "tui-check"

const width = 100

const height = 32

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..") |> normal
  use package <- promise.await(case package_fixture.start() {
    Ok(fixture) -> promise.resolve(fixture)
    Error(reason) -> panic as reason
  })
  let assert Ok(model) = terminal_fixture.start()
  let names = case argv.load().arguments {
    [] -> ["shell", "overlay", "beam"]
    names -> names
  }
  use failures <- promise.await(sequence(names, run(root, _)))
  let failures = list.flatten(failures)
  use _ <- promise.await(server.stop(package.server, True))
  use _ <- promise.map(server.stop(model, True))
  case failures {
    [] -> io.println("PASS eyg tui showed every check")
    _ -> {
      list.each(failures, io.println)
      panic as "eyg tui did not show every check"
    }
  }
}

fn normal(path) {
  case filepath.expand(path) {
    Ok(path) -> path
    Error(Nil) -> path
  }
}

/// `eyg tui` from the CLI's build, so it starts in the fixture directory.
fn command(root, name) {
  use <- bool.lazy_guard(name == "beam", fn() {
    root <> "/packages/eyg_tui/build/erlang-shipment/entrypoint.sh run"
  })
  let module =
    root <> "/packages/gleam_cli/build/dev/javascript/eyg_cli/eyg_cli.mjs"
  "bun -e \"import('"
  <> module
  <> "').then((cli) => cli.main())\" eyg tui"
  <> case name {
    "overlay" -> " overlay local.eyg"
    _ -> ""
  }
}

pub fn script(name) -> List(Step) {
  case name {
    "overlay" -> overlay()
    "beam" -> without_packages(shell())
    _ -> shell()
  }
}

fn overlay() {
  [
    Check("started", "Ask a question or describe a task to get started."),
    Type("Print a greeting and calculate 20 plus 22."),
    Key("Enter"),
    Check("answered", "Computed **42** and printed the greeting."),
    Key("C-o"),
    Check("code", "let _ = perform StandardOut(\"Hello from Gleam\")"),
    Key("C-e"),
    Check("effects", "↳ passed · {}"),
    Key("F1"),
    Check("help", "/export <file> chat"),
    Key("F1"),
    Type("/exit"),
    Key("Enter"),
  ]
}

/// The BEAM has no network, so the steps that use hub packages are left out.
fn without_packages(steps) {
  let #(before, rest) =
    list.split_while(steps, fn(step) { step != Type("@sta") })
  let after =
    list.drop_while(rest, fn(step) {
      step != Check("package used", "hub requests")
    })
  list.append(before, list.drop(after, 1))
}

fn shell() {
  [
    Check("started", "Try @standard.integer.add(20, 22)"),
    Type("perform StandardOut(\"hello\")"),
    Key("Enter"),
    Check("standard out", "▸ 1 effects"),
    Key("C-e"),
    Check("effects expanded", "↳ {}"),
    Type("let x = !int_add(20, 22)"),
    Key("Enter"),
    Type("x"),
    Key("Enter"),
    Check("binding", "42"),
    Type("/type x"),
    Key("Enter"),
    Check("type", "Integer"),
    Type("!int_add(1, \"a\")"),
    Key("Enter"),
    Check("runtime error", "expected: Integer got: \"a\""),
    Type("let y = {"),
    Key("Enter"),
    Check("incomplete input", "Continue the expression…"),
    Type("a: 1 }"),
    Key("Enter"),
    Type("y.a"),
    Key("Enter"),
    Check("continued input", "y.a"),
    Type("abc"),
    Key("Left"),
    Key("Left"),
    Type("X"),
    Key("BSpace"),
    Key("Home"),
    Type("Z"),
    Key("End"),
    Key("M-Enter"),
    Type("1"),
    Check("editing", "Zabc"),
    Key("C-u"),
    Key("BSpace"),
    Key("C-u"),
    Check("cleared", "Write EYG…"),
    Type("let banner = \"🌱緑é\" "),
    Type("import \"./gr"),
    Check("file choices", "./greeting.eyg  file"),
    Key("Tab"),
    Check("file completed", "import \"./greeting.eyg"),
    Key("C-u"),
    Type(
      "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }",
    ),
    Key("Enter"),
    Check("prompt", "Standard input"),
    Type("Corin 🌱"),
    Key("Enter"),
    Check("prompt answered", "Ok(\"Corin 🌱\")"),
    Key("F1"),
    Check("help", "/scope bindings"),
    Key("F1"),
    Resize(70, 24),
    Check("resized", "Ready"),
    Resize(width, height),
    Click("1 effects"),
    Check("effects clicked", "↳ Ok(Binary"),
    Type("let forever = (f) -> { f(f) } forever(forever)"),
    Key("Enter"),
    Check("runaway stopped", "ExecutionLimit"),
    Type("@sta"),
    Check("package choices", "@standard  hub package"),
    Key("Tab"),
    Check("package completed", "@standard"),
    Type(".integer.add(1, 2)"),
    Key("Enter"),
    Check("package used", "hub requests"),
    Type("import \"./greeting.eyg\""),
    Key("Enter"),
    Check("import", "\"hello from a file\""),
    Type("!int_add(20, 22)"),
    Key("F2"),
    Check("structure", "f2 text"),
    Key("Right"),
    Key("Right"),
    Key("n"),
    Check("structural input", "insert integer"),
    Type("40"),
    Key("Enter"),
    Check("structural edit", "!int_add(40, 22)"),
    Key("z"),
    Key("Enter"),
    Check("structural evaluation", "Vacant"),
    Key("F2"),
    Check("text again", "f2 structure"),
    Type("/exit"),
    Key("Enter"),
  ]
}

fn run(root, name) {
  io.println("Script " <> name)
  let fixture = root <> "/packages/tracing/fixtures/tui"
  let out =
    root
    <> "/packages/tracing/recordings/tui"
    <> case name {
      "overlay" -> "-overlay"
      "beam" -> "-beam"
      _ -> ""
    }
  let _ = simplifile.delete(out)
  let assert Ok(_) = simplifile.create_directory_all(out)
  // A fresh hub cache, so every run fetches the same modules.
  let cache = out <> "-cache"
  let _ = simplifile.delete(cache)
  let recorded =
    "env XDG_CACHE_HOME="
    <> cache
    <> " EYG_ORIGIN=http://127.0.0.1:7207 asciinema rec --overwrite -q -c '"
    <> string.replace(command(root, name), "'", "'\\''")
    <> "' "
    <> out
    <> ".cast"
  use _ <- promise.await(tmux(["kill-session", "-t", session]))
  use _ <- promise.await(
    tmux([
      "new-session",
      "-d",
      "-s",
      session,
      "-x",
      int.to_string(width),
      "-y",
      int.to_string(height),
      "-c",
      fixture,
      recorded,
    ]),
  )
  use failures <- promise.await(perform(script(name), out, [], 0))
  use _ <- promise.await(wait_closed(30))
  let _ = simplifile.delete(cache)
  use _ <- promise.map(tmux(["kill-session", "-t", session]))
  list.reverse(failures)
}

fn perform(steps, out, failures, index) {
  case steps {
    [] -> promise.resolve(failures)
    [step, ..rest] -> {
      use failures <- promise.await(case step {
        Type(text) -> {
          use _ <- promise.await(tmux(["send-keys", "-t", session, "-l", text]))
          use _ <- promise.map(promise.wait(150))
          failures
        }
        Key(key) -> {
          use _ <- promise.await(tmux(["send-keys", "-t", session, key]))
          use _ <- promise.map(promise.wait(150))
          failures
        }
        Resize(columns, rows) -> {
          use _ <- promise.map(
            tmux([
              "resize-window",
              "-t",
              session,
              "-x",
              int.to_string(columns),
              "-y",
              int.to_string(rows),
            ]),
          )
          failures
        }
        Click(text) -> {
          use screen <- promise.await(showing(text, 50))
          let found =
            result.unwrap(screen, "")
            |> string.split("\n")
            |> list.index_fold(Error(Nil), fn(found, line, row) {
              case found, string.split_once(line, text) {
                Error(Nil), Ok(#(before, _)) ->
                  Ok(#(string.length(before) + 1, row + 1))
                _, _ -> found
              }
            })
          case found {
            Ok(#(column, row)) -> {
              let at = int.to_string(column) <> ";" <> int.to_string(row)
              use _ <- promise.await(
                tmux([
                  "send-keys",
                  "-t",
                  session,
                  "-l",
                  "\u{1b}[<0;" <> at <> "M\u{1b}[<0;" <> at <> "m",
                ]),
              )
              use _ <- promise.map(promise.wait(150))
              failures
            }
            Error(Nil) ->
              promise.resolve(["Nothing to click shows " <> text, ..failures])
          }
        }
        Check(name, shows) -> {
          use screen <- promise.map(showing(shows, 100))
          let file =
            out
            <> "/"
            <> string.pad_start(int.to_string(index), 2, "0")
            <> "-"
            <> string.replace(name, " ", "-")
            <> ".txt"
          case screen {
            Ok(screen) -> {
              let _ = simplifile.write(file, screen)
              failures
            }
            Error(screen) -> {
              let _ = simplifile.write(file, screen)
              [
                "At " <> name <> " the screen did not show " <> shows,
                ..failures
              ]
            }
          }
        }
      })
      perform(rest, out, failures, index + 1)
    }
  }
}

/// The screen once it shows the text, checking every 100ms.
fn showing(text, attempts) {
  use screen <- promise.await(tmux(["capture-pane", "-p", "-t", session]))
  let screen = result.unwrap(screen, "")
  case string.contains(screen, text), attempts {
    True, _ -> promise.resolve(Ok(screen))
    False, 0 -> promise.resolve(Error(screen))
    False, _ -> {
      use _ <- promise.await(promise.wait(100))
      showing(text, attempts - 1)
    }
  }
}

fn wait_closed(attempts) {
  use output <- promise.await(tmux(["has-session", "-t", session]))
  case output, attempts {
    Error(_), _ -> promise.resolve(Nil)
    Ok(_), 0 -> promise.resolve(Nil)
    Ok(_), _ -> {
      use _ <- promise.await(promise.wait(200))
      wait_closed(attempts - 1)
    }
  }
}

fn sequence(items, work) {
  case items {
    [] -> promise.resolve([])
    [item, ..rest] -> {
      use first <- promise.await(work(item))
      use others <- promise.map(sequence(rest, work))
      [first, ..others]
    }
  }
}

fn tmux(arguments) {
  shellout.command("tmux", ["-L", "agent", ..arguments], ".", [])
  |> promise.resolve
}
