import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import terminal/cell
import terminal/protocol as p
import terminal/repl

fn session(arguments) {
  let events = cell.new([])
  use runtime <- promise.map(
    repl.initialize(
      arguments,
      fn(event) { cell.write(events, [event, ..cell.read(events)]) },
      fn(_) { promise.resolve("typed input") },
    ),
  )
  #(should.be_ok(runtime), events)
}

fn complete(events, id) {
  cell.read(events)
  |> list.find_map(fn(event) {
    case event {
      p.Complete(key, results, _, _) if key == id -> Ok(results)
      _ -> Error(Nil)
    }
  })
  |> should.be_ok
}

fn view(events) {
  cell.read(events)
  |> list.find_map(fn(event) {
    case event {
      p.Structural(view) -> Ok(view)
      _ -> Error(Nil)
    }
  })
  |> should.be_ok
}

pub fn scope_types_effects_and_error_recovery_test() {
  use #(runtime, events) <- promise.await(session([]))
  use Nil <- promise.await(repl.evaluate(runtime, 1, "let answer = 42", False))
  use Nil <- promise.await(repl.evaluate(
    runtime,
    2,
    "!int_add(answer, 1)",
    False,
  ))
  use Nil <- promise.await(repl.evaluate(runtime, 3, "/type answer", False))
  use Nil <- promise.await(repl.evaluate(runtime, 4, "missing", False))
  use Nil <- promise.await(repl.evaluate(runtime, 5, "answer", False))
  use Nil <- promise.map(repl.evaluate(
    runtime,
    6,
    "perform StandardOut(\"hello\")",
    False,
  ))
  complete(events, 2) |> should.equal([Ok("43")])
  complete(events, 3)
  |> list.first
  |> should.be_ok
  |> should.be_ok
  |> string.contains("Int")
  |> should.be_true
  complete(events, 4)
  |> list.first
  |> should.be_ok
  |> result.is_error
  |> should.be_true
  complete(events, 5) |> should.equal([Ok("42")])
  cell.read(events)
  |> list.contains(p.Output(6, "hello", False))
  |> should.be_true
  cell.read(events)
  |> list.contains(p.Effect(
    6,
    p.EffectRecord("StandardOut", "\"hello\"", "{}", None),
  ))
  |> should.be_true
}

pub fn shell_configuration_and_prompt_test() {
  use #(runtime, events) <- promise.await(
    session([
      "shell",
      "-c",
      "{shell: (_) -> { let seed = 9 perform Break({}) }}",
    ]),
  )
  use Nil <- promise.await(repl.evaluate(runtime, 1, "seed", False))
  use Nil <- promise.map(repl.evaluate(
    runtime,
    2,
    "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }",
    False,
  ))
  complete(events, 1) |> should.equal([Ok("9")])
  complete(events, 2)
  |> list.first
  |> should.be_ok
  |> should.be_ok
  |> string.contains("typed input")
  |> should.be_true
}

pub fn structural_edit_undo_history_and_direct_ir_test() {
  use #(runtime, events) <- promise.await(session([]))
  repl.structure(runtime, p.Enter(Some("!int_add(20, 22)")))
  repl.structure(runtime, p.Key("right"))
  repl.structure(runtime, p.Key("right"))
  repl.structure(runtime, p.Key("n"))
  view(events).input
  |> should.equal(Some(p.Input("insert integer", "20", [], "text")))
  repl.structure(runtime, p.Answer("40"))
  view(events).source |> should.equal("!int_add(40, 22)")
  repl.structure(runtime, p.Key("z"))
  view(events).source |> should.equal("!int_add(20, 22)")
  repl.structure(runtime, p.Key("Z"))
  use Nil <- promise.map(repl.evaluate(runtime, 1, "ignored", True))
  complete(events, 1) |> should.equal([Ok("62")])
  view(events).source |> should.equal("Vacant")
  repl.structure(runtime, p.Key("up"))
  view(events).source |> should.equal("!int_add(40, 22)")
  repl.structure(runtime, p.Key("down"))
  view(events).source |> should.equal("Vacant")
}

pub fn structural_effect_test() {
  use #(runtime, events) <- promise.await(session([]))
  repl.structure(runtime, p.Enter(None))
  repl.structure(runtime, p.Key("p"))
  let assert Some(input) = view(events).input
  list.any(input.hints, fn(hint) { hint.0 == "StandardOut" }) |> should.be_true
  repl.structure(runtime, p.Answer("StandardOut"))
  repl.structure(runtime, p.Key(" "))
  repl.structure(runtime, p.Key("s"))
  repl.structure(runtime, p.Answer("structural hello"))
  use Nil <- promise.map(repl.evaluate(runtime, 1, "", True))
  cell.read(events)
  |> list.contains(p.Effect(
    1,
    p.EffectRecord("StandardOut", "\"structural hello\"", "{}", None),
  ))
  |> should.be_true
}

pub fn binary_clipboard_and_cross_mode_definitions_test() {
  use #(runtime, events) <- promise.await(session([]))
  repl.structure(runtime, p.Enter(None))
  repl.structure(runtime, p.Key("b"))
  repl.structure(runtime, p.Key("y"))
  let copied =
    cell.read(events)
    |> list.find_map(fn(event) {
      case event {
        p.Clipboard(text) -> Ok(text)
        _ -> Error(Nil)
      }
    })
    |> should.be_ok
  string.contains(copied, "\"0\"") |> should.be_true
  repl.structure(runtime, p.Key("d"))
  repl.structure(runtime, p.Paste(copied))
  repl.structure(runtime, p.Key("e"))
  repl.structure(runtime, p.Answer("bytes"))
  use Nil <- promise.await(repl.evaluate(runtime, 1, "", True))
  use Nil <- promise.map(repl.evaluate(runtime, 2, "/type bytes", False))
  complete(events, 2)
  |> list.first
  |> should.be_ok
  |> should.be_ok
  |> string.contains("Binary")
  |> should.be_true
}

pub fn failed_structural_run_and_invalid_input_preserve_expression_test() {
  use #(runtime, events) <- promise.await(session([]))
  repl.structure(runtime, p.Enter(Some("!int_add(20, \"wrong\")")))
  use Nil <- promise.await(repl.evaluate(runtime, 1, "", True))
  complete(events, 1)
  |> list.first
  |> should.be_ok
  |> result.is_error
  |> should.be_true
  view(events).source |> should.equal("!int_add(20, \"wrong\")")
  repl.structure(runtime, p.Focus([2]))
  repl.structure(runtime, p.Key("n"))
  repl.structure(runtime, p.Answer("invalid"))
  view(events).message |> should.equal(Some("Enter an integer"))
  repl.structure(runtime, p.Answer("22"))
  use Nil <- promise.map(repl.evaluate(runtime, 2, "", True))
  complete(events, 2) |> should.equal([Ok("42")])
  view(events).errors |> should.equal([])
}

pub fn local_reference_types_arrive_without_losing_import_test() {
  let events = cell.new([])
  let #(loaded, resolve) = promise.start()
  use initialized <- promise.await(
    repl.initialize(
      [],
      fn(event) {
        cell.write(events, [event, ..cell.read(events)])
        case event {
          p.Structural(p.View(errors: [], type_: type_, ..)) -> {
            case string.contains(type_, "count") {
              True -> resolve(Nil)
              False -> Nil
            }
          }
          _ -> Nil
        }
      },
      fn(_) { promise.resolve("") },
    ),
  )
  let runtime = should.be_ok(initialized)
  repl.structure(
    runtime,
    p.Enter(Some("import \"../overlay_tui/test/fixtures/module.eyg\"")),
  )
  use Nil <- promise.map(loaded)
  repl.structure(runtime, p.Key("g"))
  let assert Some(input) = view(events).input
  list.contains(input.hints, #("count", "Integer")) |> should.be_true
  repl.structure(runtime, p.Answer("count"))
  view(events).type_ |> should.equal("Integer")
  view(events).source |> string.contains("module.eyg") |> should.be_true
}
