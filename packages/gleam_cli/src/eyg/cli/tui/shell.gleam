//// The shell as a value. Starting and evaluating return effects that the tui
//// advances itself: output and input belong to the screen, and loam performs
//// every other operation.

import eyg/cli/internal/config
import eyg/cli/shell as repl
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/ir/tree
import gleam/dict
import gleam/http/request
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/uri
import loam/execute
import loam/system
import plinthx/browser/performance
import plinthx/node/util

pub type Shell {
  Shell(
    scope: execute.Scope,
    definitions: List(#(String, tree.Node(#(Int, Int)), #(Int, Int))),
    execution: execute.State,
    pending: String,
  )
}

/// An EYG effect performed by an evaluation, as text.
pub type Performed {
  Performed(label: String, input: String, output: String)
}

pub type Evaluated {
  Evaluated(
    results: List(Result(String, String)),
    performed: List(Performed),
    shell: Shell,
  )
}

pub fn start(input, config: config.Config) {
  use started <- system.map(repl.initialize(input, config))
  use #(scope, execution) <- result.map(started)
  Shell(scope:, definitions: [], execution:, pending: "")
}

/// Evaluate source, continuing an incomplete expression from before.
pub fn evaluate(shell: Shell, source) {
  let code = case shell.pending {
    "" -> source
    pending -> pending <> "\n" <> source
  }
  repl.handle_recorded(code, shell.scope, shell.definitions, shell.execution)
  |> system.map(evaluated)
}

/// Evaluate structural IR directly, keeping binary values and vacant nodes.
pub fn evaluate_ir(shell: Shell, code) {
  repl.handle_source_recorded(
    code,
    shell.scope,
    shell.definitions,
    shell.execution,
  )
  |> system.map(evaluated)
}

fn evaluated(result) {
  let #(results, records, #(pending, scope, definitions, execution)) = result
  let performed =
    list.map(records, fn(record) {
      let #(label, input, output) = record
      Performed(
        label,
        simple_debug.inspect(input),
        simple_debug.inspect(output),
      )
    })
  Evaluated(
    results,
    performed,
    Shell(scope:, definitions:, execution:, pending:),
  )
}

/// Keep whichever published package ledger was pulled further, so packages
/// found in the background survive evaluations that started before them.
pub fn with_ledger(shell: Shell, from: execute.State) -> Shell {
  let current = shell.execution.cache
  let other = from.cache
  case other.cursor > current.cursor {
    False -> shell
    True -> {
      let cache =
        cache.Cache(
          ..current,
          packages: other.packages,
          releases: dict.merge(current.releases, other.releases),
          cursor: other.cursor,
          cursor_status: other.cursor_status,
        )
      Shell(..shell, execution: execute.State(..shell.execution, cache:))
    }
  }
}

/// Published package names, sorted.
pub fn packages(shell: Shell) {
  dict.keys(shell.execution.cache.packages) |> list.sort(string.compare)
}

/// What happened while advancing, for the screen.
pub type Event {
  Output(text: String, error: Bool)
  Fetched(url: String)
}

pub type Progress(a) {
  Finished(a)
  Asking(prompt: String, resume: fn(String) -> system.Effect(a))
  Exited(status: Int)
  Paused(system.Effect(a))
}

/// Advance an effect until it finishes, asks for input or exits, or until
/// `budget` milliseconds have passed, so the screen keeps up with long work.
pub fn advance(
  effect: system.Effect(a),
  budget: Float,
) -> Promise(#(List(Event), Progress(a))) {
  use #(events, progress) <- promise.map(go(effect, [], now() +. budget))
  #(list.reverse(events), progress)
}

fn go(effect, events, deadline) {
  let print = fn(text, error, resume) {
    go(resume(Nil), [Output(clean(text), error), ..events], deadline)
  }
  case effect {
    system.Done(value) -> promise.resolve(#(events, Finished(value)))
    system.Exit(status) -> promise.resolve(#(events, Exited(status)))
    system.Prompt(text, resume) ->
      promise.resolve(#(
        events,
        Asking(last_line(text), fn(answer) { resume(Ok(answer)) }),
      ))
    system.Stdin(resume) ->
      promise.resolve(#(
        events,
        Asking("Standard input", fn(answer) { resume(Ok(answer)) }),
      ))
    _ ->
      case now() >. deadline {
        True -> promise.resolve(#(events, Paused(effect)))
        False ->
          case effect {
            system.Stdout(text, resume) -> print(text <> "\n", False, resume)
            system.WriteStdout(text, resume) -> print(text, False, resume)
            system.WriteStderr(text, resume) -> print(text, True, resume)
            system.Fetch(request, _) -> {
              let events = [Fetched(public_url(request)), ..events]
              promise.await(system.step(effect), go(_, events, deadline))
            }
            _ -> promise.await(system.step(effect), go(_, events, deadline))
          }
      }
  }
}

fn last_line(text) {
  clean(text) |> string.split("\r") |> list.last |> result.unwrap("")
}

fn clean(text) {
  util.strip_vt_control_characters(text)
}

fn public_url(req) {
  let parsed = request.to_uri(req)
  uri.to_string(uri.Uri(..parsed, userinfo: None, query: None, fragment: None))
}

pub fn now() -> Float {
  let assert Ok(clock) = performance.get()
  performance.now(clock)
}
