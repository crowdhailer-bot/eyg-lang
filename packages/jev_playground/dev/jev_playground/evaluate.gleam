//// Run an eval against the real API until the checker accepts the program.
//// Every step is saved so the run can be replayed at real speed and recorded.
//// `TYPESAFE_API_KEY=... gleam run -m jev_playground/evaluate --runtime bun -- fibonacci [flags]`, the flags are listed at `eval.variant`.

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import jev
import jev_playground/action
import jev_playground/agent
import jev_playground/client
import jev_playground/environment
import jev_playground/eval
import jev_playground/library
import jev_playground/options
import jev_playground/packages
import plinth/javascript/date
import plinth/node/process
import simplifile

pub const directory = "recordings/evals"

pub type Outcome {
  Solved
  OutOfSteps
  /// Three choices in a row below 0.2 confidence, no run that did this was solved.
  Unsure
  Failed(reason: String)
}

pub fn main() {
  let assert [slug, ..flags] = argv.load().arguments
  let assert Ok(the_eval) = eval.find(slug)
  let variant = eval.variant(flags)
  let assert Ok(key) =
    list.key_find(array.to_list(process.env()), "TYPESAFE_API_KEY")
  use summary <- promise.map(run(the_eval, variant, client.Direct(key)))
  io.println(summary_line(summary))
}

pub type Summary {
  Summary(
    eval: String,
    variant: String,
    solved: Bool,
    outcome: String,
    steps: Int,
    /// Several steps are taken from one request when Jev fills several holes.
    requests: Int,
    compound_steps: Int,
    tokens: Int,
    cost: Float,
    seconds: Float,
    file: String,
  )
}

/// Run the eval and save every step.
pub fn run(
  the_eval: eval.Eval,
  variant,
  transport,
) -> promise.Promise(Summary) {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, environment.pure())
  let assert Ok(start) = eval.start(the_eval)
  let config = eval.config(the_eval, variant)
  let agent = agent.new(the_eval.task, start, environment, config)
  let started = client.now()
  use #(agent, outcome) <- promise.map(loop(agent, the_eval, transport))
  let seconds = { client.now() -. started } /. 1000.0
  let steps = list.reverse(agent.history)
  let tokens = int.sum(list.map(steps, fn(step) { step.input_tokens }))
  let thinking = int.sum(list.map(steps, fn(step) { step.thinking_ms }))
  let cost = int.to_float(tokens) *. 0.042 /. 1_000_000.0
  let name = the_eval.slug <> "-" <> eval.variant_name(variant)
  let file = name <> "-" <> int.to_string(date.get_time(date.now())) <> ".json"
  let outcome_text = case outcome {
    Solved -> "solved"
    OutOfSteps -> "out of steps"
    Unsure -> "stopped unsure"
    Failed(reason) -> "failed: " <> reason
  }
  let record =
    json.object([
      #("eval", json.string(the_eval.slug)),
      #("variant", json.string(eval.variant_name(variant))),
      #("compounds", json.int(variant.compounds)),
      #("instances", json.int(variant.instances)),
      #("slot_questions", json.bool(variant.slot_questions)),
      #("type_filter", json.bool(variant.type_filter)),
      #("no_repeats", json.bool(variant.no_repeats)),
      #("focus_holes", json.bool(variant.focus_holes)),
      #("hole_types", json.bool(variant.hole_types)),
      #("cursors", json.int(variant.cursors)),
      #("jumps", json.bool(variant.jumps)),
      #("highlight", json.string(options.highlight_name(variant.highlight))),
      #("check_compounds", json.bool(variant.check_compounds)),
      #("outcome", json.string(outcome_text)),
      #("steps", json.array(steps, agent.step_to_json)),
      #("input_tokens", json.int(tokens)),
      #("cost_usd", json.float(cost)),
      #("seconds", json.float(seconds)),
      #("thinking_ms", json.int(thinking)),
      #("program", json.string(agent.program_text(agent))),
    ])
  let _ = simplifile.create_directory_all(directory)
  let assert Ok(Nil) =
    simplifile.write(directory <> "/" <> file, json.to_string(record))
  let compound_steps =
    list.count(steps, fn(step) {
      case step.action {
        action.Compound(..) -> True
        _ -> False
      }
    })
  Summary(
    eval: the_eval.slug,
    variant: eval.variant_name(variant),
    solved: outcome == Solved,
    outcome: outcome_text,
    steps: list.length(steps),
    requests: requests(steps),
    compound_steps:,
    tokens:,
    cost:,
    seconds:,
    file:,
  )
}

pub fn summary_line(summary: Summary) {
  string.join(
    [
      summary.eval <> "-" <> summary.variant,
      summary.outcome,
      int.to_string(summary.steps) <> " steps",
      int.to_string(summary.requests) <> " requests",
      int.to_string(summary.tokens) <> " tokens",
      "$" <> float.to_string(float.to_precision(summary.cost, 4)),
      float.to_string(float.to_precision(summary.seconds, 1)) <> "s",
      summary.file,
    ],
    " | ",
  )
}

// The last three requests were answered with less than 0.2 confidence.
fn unsure(steps: List(agent.Step)) {
  case list.filter(steps, fn(step) { step.input_tokens > 0 }) {
    [a, b, c, ..] ->
      a.confidence <. 0.2 && b.confidence <. 0.2 && c.confidence <. 0.2
    _ -> False
  }
}

// Steps filling extra holes are taken without a request of their own.
fn requests(steps: List(agent.Step)) {
  list.count(steps, fn(step) { step.input_tokens > 0 })
}

fn loop(agent: agent.Agent, the_eval: eval.Eval, transport) {
  case requests(agent.history) >= the_eval.max_steps {
    True -> promise.resolve(#(agent, OutOfSteps))
    False -> {
      let before = list.length(agent.history)
      let #(request, offered) = agent.request(agent, jev.latest)
      use reply <- promise.await(client.system_one(transport, request))
      case reply {
        Error(reason) -> promise.resolve(#(agent, Failed(reason)))
        Ok(client.Reply(evaluation:, thinking_ms:)) ->
          case agent.answer(agent, offered, evaluation, thinking_ms) {
            Error(reason) -> promise.resolve(#(agent, Failed(reason)))
            Ok(agent) -> {
              let assert [step, ..] = agent.history
              let #(agent, solved) = eval.after_step(the_eval, agent, step)
              list.take(agent.history, list.length(agent.history) - before)
              |> list.reverse
              |> list.index_map(fn(step, i) {
                io.println(
                  string.pad_start(int.to_string(before + i + 1), 4, " ")
                  <> " "
                  <> step.label
                  <> case step.failed {
                    True -> " (failed)"
                    False -> ""
                  }
                  <> " "
                  <> float.to_string(float.to_precision(step.confidence, 2))
                  <> " "
                  <> int.to_string(step.thinking_ms)
                  <> "ms",
                )
              })
              case solved, unsure(agent.history) {
                True, _ -> promise.resolve(#(agent, Solved))
                False, True -> promise.resolve(#(agent, Unsure))
                False, False -> loop(agent, the_eval, transport)
              }
            }
          }
      }
    }
  }
}
