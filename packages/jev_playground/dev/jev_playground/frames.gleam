//// Replay saved eval runs into the frames of a video: for each step the
//// program as it stood, coloured, with the time Jev took to choose it.
//// `gleam run -m jev_playground/frames --runtime bun -- out.json <run> ...`,
//// a run named as its file in `recordings/evals` without `.json`.

import argv
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import jev_playground/agent
import jev_playground/dnsimple
import jev_playground/environment
import jev_playground/eval
import jev_playground/evaluate
import jev_playground/highlight
import jev_playground/hub
import jev_playground/library
import jev_playground/packages
import lustre/element
import morph/buffer
import morph/editable as e
import simplifile

pub fn main() {
  let assert [out, ..names] = argv.load().arguments
  use environment <- promise.map(context_environment())
  let runs = list.filter_map(names, frames(_, environment))
  let assert Ok(Nil) =
    simplifile.write(out, json.to_string(json.array(runs, run_to_json)))
  io.println(
    int.to_string(list.length(runs))
    <> " runs written to "
    <> out
    <> ", "
    <> int.to_string(list.length(names) - list.length(runs))
    <> " could not be replayed",
  )
}

/// A run as it is played: the question, and a frame for each edit.
pub type Run {
  Run(
    name: String,
    task: String,
    seconds: Float,
    steps: Int,
    /// How the run ended: solved, or why not.
    outcome: String,
    frames: List(Frame),
  )
}

pub type Frame {
  Frame(
    code: String,
    label: String,
    confidence: Float,
    thinking_ms: Int,
    output: String,
  )
}

fn frames(name, environment) {
  use saved <- result.try(
    simplifile.read(evaluate.directory <> "/" <> name <> ".json")
    |> result.replace_error(Nil),
  )
  use run <- result.try(
    json.parse(saved, eval.run_decoder()) |> result.replace_error(Nil),
  )
  let eval.Run(eval: the_eval, variant:, steps:, outcome:) = run
  let config = eval.config(the_eval, variant)
  let start = agent.new(the_eval.task, e.Vacant, environment, config)
  let #(_agent, frames) =
    list.map_fold(steps, start, fn(agent, step: agent.Step) {
      let agent = agent.take(agent, step) |> result.unwrap(agent)
      let output = case agent.is_complete(agent) {
        True -> eval.output(the_eval, buffer.source(agent.buffer), environment)
        False -> ""
      }
      #(
        agent,
        Frame(
          code: coloured(agent),
          label: step.label,
          confidence: step.confidence,
          thinking_ms: step.thinking_ms,
          output:,
        ),
      )
    })
  let thinking =
    list.fold(steps, 0, fn(total, step: agent.Step) { total + step.thinking_ms })
  Ok(Run(
    name:,
    task: the_eval.task,
    seconds: int.to_float(thinking) /. 1000.0,
    steps: list.length(steps),
    outcome:,
    frames:,
  ))
}

// The program as HTML, coloured by the same code as the playground and the overlay.
fn coloured(agent) {
  agent.program_text(agent)
  |> highlight.highlight_program
  |> element.fragment
  |> element.to_string
}

fn run_to_json(run: Run) {
  let Run(name:, task:, seconds:, steps:, outcome:, frames:) = run
  json.object([
    #("name", json.string(name)),
    #("task", json.string(task)),
    #("seconds", json.float(seconds)),
    #("steps", json.int(steps)),
    #("outcome", json.string(outcome)),
    #(
      "frames",
      json.array(frames, fn(frame: Frame) {
        json.object([
          #("code", json.string(frame.code)),
          #("label", json.string(frame.label)),
          #("confidence", json.float(frame.confidence)),
          #("thinking_ms", json.int(frame.thinking_ms)),
          #("output", json.string(frame.output)),
        ])
      }),
    ),
  ])
}

// The environment the DNSimple questions run in, as the eval runner builds it.
fn context_environment() {
  use source <- promise.map(hub.module(dnsimple.context_id))
  let assert Ok(source) = source
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(base) = library.environment(bundle, environment.browser())
  let assert Ok(environment) = library.context(source, base)
  environment
}
