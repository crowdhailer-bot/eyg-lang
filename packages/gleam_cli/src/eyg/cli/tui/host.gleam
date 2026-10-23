//// What differs between targets for the tui. On JavaScript the terminal and
//// the shell's work answer with promises, and effects run with loam. On the
//// BEAM they answer at once.

import eyg/cli/tui/shell.{Asking, Exited, Fetched, Finished, Output, Paused}
import gleam/list
import gleam/option.{None}
import gleam/result
import loam/system

@target(javascript)
import gleam/javascript/promise.{type Promise}

@target(javascript)
import plinthx/javascript/string

@target(erlang)
import envoy

@target(erlang)
import gleam/float

@target(erlang)
import gleam/int

@target(erlang)
import gleam/string

@target(erlang)
import midas/effect as midas

@target(erlang)
import simplifile

@target(javascript)
/// A value that is ready later.
pub type Pending(a) =
  Promise(a)

@target(javascript)
pub fn resolve(value: a) -> Pending(a) {
  promise.resolve(value)
}

@target(javascript)
pub fn map(pending: Pending(a), f: fn(a) -> b) -> Pending(b) {
  promise.map(pending, f)
}

@target(javascript)
pub fn await(pending: Pending(a), then: fn(a) -> Pending(b)) -> Pending(b) {
  promise.await(pending, then)
}

@target(javascript)
/// The first of the values to be ready, or `otherwise` after `milliseconds`.
pub fn first(pending: List(Pending(a)), milliseconds, otherwise: a) {
  let waited = promise.map(promise.wait(milliseconds), fn(_) { otherwise })
  promise.race_list([waited, ..pending])
}

@target(javascript)
/// Run an effect to the end with loam, or the error that stopped it.
pub fn run(effect: system.Effect(a)) -> Pending(Result(a, String)) {
  system.run(effect)
  |> promise.map(Ok)
  |> promise.rescue(failure)
}

@target(javascript)
/// Advance an effect until it finishes, asks for input or exits, or until
/// `budget` milliseconds have passed, so the screen keeps up with long work.
pub fn advance(effect: system.Effect(a), budget: Float) {
  go(effect, [], shell.now() +. budget)
  |> promise.map(fn(advanced) {
    let #(events, progress) = advanced
    Ok(#(list.reverse(events), progress))
  })
  |> promise.rescue(failure)
}

@target(javascript)
fn failure(error) {
  Error(string.from(error) |> result.unwrap("Unknown JavaScript error"))
}

@target(javascript)
fn go(effect, events, deadline) {
  let print = fn(text, error, resume) {
    go(resume(Nil), [Output(shell.clean(text), error), ..events], deadline)
  }
  case effect {
    system.Done(value) -> promise.resolve(#(events, Finished(value)))
    system.Exit(status) -> promise.resolve(#(events, Exited(status)))
    system.Prompt(text, resume) ->
      promise.resolve(#(
        events,
        Asking(shell.prompt_text(text), fn(answer) { resume(Ok(answer)) }),
      ))
    system.Stdin(resume) ->
      promise.resolve(#(
        events,
        Asking("Standard input", fn(answer) { resume(Ok(answer)) }),
      ))
    // The tui owns the keyboard, so no key reaches the program.
    system.ReadKey(milliseconds, resume) ->
      promise.await(promise.wait(milliseconds), fn(_) {
        go(resume(None), events, deadline)
      })
    _ ->
      case shell.now() >. deadline {
        True -> promise.resolve(#(events, Paused(effect)))
        False ->
          case effect {
            system.Stdout(text, resume) -> print(text <> "\n", False, resume)
            system.WriteStdout(text, resume) -> print(text, False, resume)
            system.WriteStderr(text, resume) -> print(text, True, resume)
            system.Fetch(request, _) | system.FetchStream(request, _) -> {
              let events = [Fetched(shell.public_url(request)), ..events]
              promise.await(system.step(effect), go(_, events, deadline))
            }
            _ -> promise.await(system.step(effect), go(_, events, deadline))
          }
      }
  }
}

// On the BEAM every value is ready at once. Effects are interpreted in the
// tui's process: output, prompts and standard input go to the screen, files,
// the environment, the time and randomness are available, network requests and
// writes fail and every other operation stops the evaluation.

@target(erlang)
pub type Pending(a) =
  a

@target(erlang)
pub fn resolve(value: a) -> Pending(a) {
  value
}

@target(erlang)
pub fn map(pending: Pending(a), f: fn(a) -> b) -> Pending(b) {
  f(pending)
}

@target(erlang)
pub fn await(pending: Pending(a), then: fn(a) -> Pending(b)) -> Pending(b) {
  then(pending)
}

@target(erlang)
pub fn first(pending: List(Pending(a)), _milliseconds, otherwise: a) -> a {
  case pending {
    [ready, ..] -> ready
    [] -> otherwise
  }
}

@target(erlang)
/// Run an effect to the end, or the reason it stopped.
pub fn run(effect: system.Effect(a)) -> Result(a, String) {
  case advance(effect, 0.0) {
    Ok(#(_, Finished(value))) -> Ok(value)
    Ok(#(_, Asking(..))) -> Error("Input is not available here")
    Ok(#(_, Exited(status))) ->
      Error("Exited with status " <> int.to_string(status))
    Ok(#(_, Paused(effect))) -> run(effect)
    Error(reason) -> Error(reason)
  }
}

@target(erlang)
/// Advance an effect until it finishes, asks for input or exits.
pub fn advance(effect: system.Effect(a), _budget: Float) {
  case go(effect, []) {
    Ok(#(events, progress)) -> Ok(#(list.reverse(events), progress))
    Error(reason) -> Error(reason)
  }
}

@target(erlang)
fn go(effect, events) {
  let print = fn(text, error, resume) {
    go(resume(Nil), [Output(shell.clean(text), error), ..events])
  }
  let fail = fn(path) { simplifile.Unknown(path <> " " <> unavailable) }
  case effect {
    system.Done(value) -> Ok(#(events, Finished(value)))
    system.Exit(status) -> Ok(#(events, Exited(status)))
    system.Prompt(text, resume) ->
      Ok(#(
        events,
        Asking(shell.prompt_text(text), fn(answer) { resume(Ok(answer)) }),
      ))
    system.Stdin(resume) ->
      Ok(#(events, Asking("Standard input", fn(answer) { resume(Ok(answer)) })))
    system.Stdout(text, resume) -> print(text <> "\n", False, resume)
    system.WriteStdout(text, resume) -> print(text, False, resume)
    system.WriteStderr(text, resume) -> print(text, True, resume)
    // The tui owns the keyboard, so no key reaches the program.
    system.ReadKey(_, resume) -> go(resume(None), events)
    system.SpanStart(_, _, resume) -> go(resume(Nil), events)
    system.SpanEnd(_, resume) -> go(resume(Nil), events)
    system.Cwd(resume) ->
      simplifile.current_directory()
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> go(events)
    system.Env(name, resume) ->
      go(resume(envoy.get(name) |> option.from_result), events)
    system.Now(resume) -> go(resume(float.round(shell.now())), events)
    system.Random(max, resume) -> go(resume(int.random(max)), events)
    system.ReadFile(path, resume) ->
      simplifile.read(path)
      |> result.map_error(system.format_file_error(path, _))
      |> resume
      |> go(events)
    system.ReadDirectory(path, resume) ->
      go(resume(simplifile.read_directory(path)), events)
    system.FileInfo(path, resume) ->
      simplifile.file_info(path)
      |> result.map(fn(info) {
        system.Metadata(simplifile.file_info_type(info), info.size)
      })
      |> resume
      |> go(events)
    system.Fetch(request, resume) -> {
      let events = [Fetched(shell.public_url(request)), ..events]
      go(resume(Error(midas.NetworkError(unavailable))), events)
    }
    system.FetchStream(request, resume) -> {
      let events = [Fetched(shell.public_url(request)), ..events]
      go(resume(Error(midas.NetworkError(unavailable))), events)
    }
    // Files are only read, so the hub cache is not kept between sessions.
    system.ReadFileRange(path:, resume:, ..) ->
      go(resume(Error(fail(path))), events)
    system.WriteFile(path, _, resume) ->
      go(resume(Error(fail(path) |> simplifile.describe_error)), events)
    system.WriteFileBits(path, _, resume) ->
      go(resume(Error(fail(path))), events)
    system.AppendFileBits(path, _, resume) ->
      go(resume(Error(fail(path))), events)
    system.DeleteFile(path, resume) -> go(resume(Error(fail(path))), events)
    system.CreateDirectory(path, resume) ->
      go(resume(Error(fail(path) |> simplifile.describe_error)), events)
    _ -> Error(operation(effect) <> " " <> unavailable)
  }
}

@target(erlang)
const unavailable = "needs the JavaScript runtime"

@target(erlang)
/// The name of an operation, such as `Hash`.
fn operation(effect) {
  case string.split_once(string.inspect(effect), "(") {
    Ok(#(name, _)) -> name
    Error(Nil) -> "This operation"
  }
}
