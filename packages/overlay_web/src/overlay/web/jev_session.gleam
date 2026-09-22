//// A question answered by Jev. Jev builds a program one structural edit at a
//// time, with the context module in scope and its readme in every request, and
//// the program then runs like any other with the overlay's effects.

import eyg/hub/cache
import gleam/dict
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/result
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
pub fn new(question: String, context: cache.Module(tools.Meta)) -> agent.Agent {
  let environment =
    environment.Environment(
      ..environment.browser(),
      scope: [#("context", context.type_)],
      values: [#("context", context.value)],
    )
  let config = options.Config(..options.default_config(), focus_holes: True)
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

pub type Next {
  /// Ask Jev for the next edit.
  Ask(agent: agent.Agent)
  /// The program is complete, run it.
  Run(agent: agent.Agent, call: tool.Call)
  /// Jev did not finish, with the reason.
  GiveUp(agent: agent.Agent, reason: String)
}

/// Apply the edit Jev chose and decide what comes next.
pub fn answered(
  agent: agent.Agent,
  offered: List(options.Option),
  evaluation: jev.Evaluation,
) -> Result(Next, String) {
  use agent <- result.map(agent.answer(agent, offered, evaluation, 0))
  next(agent)
}

pub fn next(agent: agent.Agent) -> Next {
  case agent.is_complete(agent), requests(agent) >= max_requests {
    True, _ -> Run(agent, run_call(agent))
    False, True ->
      GiveUp(
        agent,
        "Jev did not finish a program in "
          <> int.to_string(max_requests)
          <> " edits.",
      )
    False, False ->
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

/// The program as text, as the run tool is given it.
pub fn program(agent: agent.Agent) -> String {
  text.print(agent.source(agent))
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
