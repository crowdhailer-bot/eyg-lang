//// A question answered by Jev. Jev builds a program one structural edit at a
//// time, with the context module in scope and its readme in every request, and
//// the program then runs like any other with the overlay's effects.

import eyg/hub/cache
import gleam/dict
import gleam/float
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev
import jev_playground/agent
import jev_playground/environment
import jev_playground/options
import morph/editable as e
import morph/text
import oas/generator/utils
import ogre/operation
import ogre/origin
import overlay/llm/tool
import overlay/web/tools

/// A question Jev cannot answer within this many requests is given up.
pub const max_requests = 30

/// Start from an empty program, filling one hole at a time.
/// Effects are shown only on the calls of context functions that perform them,
/// which solved as many questions as any way of showing them for the fewest tokens.
pub fn new(
  question: String,
  context: cache.Module(tools.Meta),
  libraries: List(environment.Library),
) -> agent.Agent {
  let environment =
    environment.Environment(
      ..environment.browser(),
      libraries:,
      scope: [#("context", context.type_)],
      values: [#("context", context.value)],
    )
  let config =
    options.Config(
      ..options.default_config(),
      focus_holes: True,
      effects: options.EffectCallsOnly,
    )
  agent.new(question, e.Vacant, environment, config)
}

/// The request for the next edit. It is sent to the page's origin, which
/// forwards `/v1` to TypeSafe, with the person's own key.
pub fn request(
  agent: agent.Agent,
  model: String,
  api_key: String,
  origin: origin.Origin,
) -> #(Request(BitArray), List(options.Option)) {
  let #(request, offered) = agent.request(agent, model)
  let http =
    jev.system_one(request)
    |> jev.authorize(api_key)
    |> operation.to_request(origin)
  #(http, offered)
}

/// The program last run and what it returned.
pub type LastRun {
  LastRun(program: String, output: String)
}

pub type Next {
  /// Ask Jev for the next edit.
  Ask(agent: agent.Agent)
  /// Run the complete program, `finished` when Jev has said it is the answer.
  Run(agent: agent.Agent, call: tool.Call, finished: Bool)
  /// Jev finished with the program last run, whose output is the answer.
  Done(agent: agent.Agent, output: String)
  /// Jev did not finish, with the reason.
  GiveUp(agent: agent.Agent, reason: String)
}

/// Apply the edit Jev chose and decide what comes next.
pub fn answered(
  agent: agent.Agent,
  offered: List(options.Option),
  evaluation: jev.Evaluation,
  last: Option(LastRun),
) -> Result(Next, String) {
  use agent <- result.map(agent.answer(agent, offered, evaluation, 0))
  next(agent, last)
}

/// Jev is shown what each new complete program returns, and the answer is the
/// program it finishes with. A program runs again only if it has changed, as a
/// run may change the account.
pub fn next(agent: agent.Agent, last: Option(LastRun)) -> Next {
  let program = program(agent)
  let ran = case last {
    Some(LastRun(program: ran, output:)) if ran == program -> Some(output)
    _ -> None
  }
  case agent.is_complete(agent), agent.finished, ran {
    True, True, Some(output) -> Done(agent, output)
    True, True, None -> Run(agent, run_call(agent), True)
    False, True, _ -> {
      let results = Some("the program still has holes")
      limited(agent.Agent(..agent, finished: False, test_results: results))
    }
    True, False, None -> Run(agent, run_call(agent), False)
    _, _, _ -> limited(agent)
  }
}

fn limited(agent: agent.Agent) -> Next {
  case requests(agent) >= max_requests {
    True ->
      GiveUp(
        agent,
        "Jev did not finish a program in "
          <> int.to_string(max_requests)
          <> " edits.",
      )
    False ->
      case unsure(agent) {
        True ->
          GiveUp(
            agent,
            "Jev was unsure of three edits in a row, try asking another way.",
          )
        False -> Ask(agent)
      }
  }
}

/// The program as text, as the run tool is given it, with releases pinned.
pub fn program(agent: agent.Agent) -> String {
  text.print(agent.source(agent))
}

/// The program as a person reads it, a release written as its package name.
pub fn shown_program(agent: agent.Agent) -> String {
  environment.shorten_packages(program(agent), agent.environment)
}

/// Every edit Jev made, oldest first, for the list of what it did.
pub fn edits(agent: agent.Agent) -> String {
  list.reverse(agent.history)
  |> list.index_map(fn(step: agent.Step, i) {
    int.to_string(i + 1)
    <> ". "
    <> string.replace(step.label, "\n", " ")
    <> "  "
    <> float.to_string(float.to_precision(step.confidence, 2))
    <> "  "
    <> int.to_string(step.thinking_ms)
    <> "ms"
  })
  |> string.join("\n")
}

fn run_call(agent) {
  tool.Call(
    id: "jev",
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String(program(agent)))]),
    ),
  )
}

// Extra holes filled in the same request have no tokens of their own.
fn requests(agent: agent.Agent) {
  list.count(agent.history, fn(step) { step.input_tokens > 0 })
}

// No run that made three choices in a row below 0.2 confidence recovered.
fn unsure(agent: agent.Agent) {
  case list.filter(agent.history, fn(step) { step.input_tokens > 0 }) {
    [a, b, c, ..] ->
      a.confidence <. 0.2 && b.confidence <. 0.2 && c.confidence <. 0.2
    _ -> False
  }
}
