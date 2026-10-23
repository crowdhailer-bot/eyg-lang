//// What differs between targets for the tui. On JavaScript the terminal and
//// the shell's work answer with promises, and effects run with loam.

@target(javascript)
import eyg/cli/tui/shell.{Asking, Exited, Fetched, Finished, Output, Paused}

@target(javascript)
import gleam/javascript/promise.{type Promise}

@target(javascript)
import gleam/list

@target(javascript)
import gleam/option.{None}

@target(javascript)
import gleam/result

@target(javascript)
import loam/system

@target(javascript)
import plinthx/javascript/string

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
