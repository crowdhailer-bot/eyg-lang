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
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/regexp
import gleam/result
import gleam/string
import gleam/time/timestamp
import gleam/uri
import loam/execute
import loam/system

pub type Shell {
  Shell(
    scope: execute.Scope,
    definitions: List(#(String, tree.Node(#(Int, Int)), #(Int, Int))),
    execution: execute.State,
    pending: String,
  )
}

/// An EYG effect performed by an evaluation, as text, and what a policy decided.
pub type Performed {
  Performed(
    label: String,
    input: String,
    output: String,
    decision: Option(String),
  )
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
        None,
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

/// The last line of a prompt, as the editor shows it.
pub fn prompt_text(text) {
  clean(text) |> string.split("\r") |> list.last |> result.unwrap("")
}

/// Remove terminal control sequences from output.
pub fn clean(text) {
  let assert Ok(control) =
    regexp.from_string(
      "[\u{1b}\u{9b}][\\[\\]()#;?]*(?:\\d{1,4}(?:[;:]\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]",
    )
  regexp.replace(control, text, "")
}

pub fn public_url(req) {
  let parsed = request.to_uri(req)
  uri.to_string(uri.Uri(..parsed, userinfo: None, query: None, fragment: None))
}

/// Milliseconds since the epoch.
pub fn now() -> Float {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  int.to_float(seconds) *. 1000.0 +. int.to_float(nanoseconds) /. 1_000_000.0
}
