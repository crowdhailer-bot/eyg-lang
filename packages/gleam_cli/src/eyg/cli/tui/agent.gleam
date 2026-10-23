//// An Overlay agent as a value. Each step of a turn is an effect the tui
//// advances: streamed assistant text is written to standard output, so it
//// reaches the entry being generated.

import eyg/cli/internal/config
@target(javascript)
import eyg/cli/internal/traces

import eyg/cli/overlay as cli
import eyg/cli/tui/shell
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import loam/execute
import loam/system
import oas/generator/utils
import overlay/agent
import overlay/llm/chat
import overlay/llm/tool
import touch_grass/harness/computer

pub type Agent {
  Agent(
    session: cli.Session(computer.Effect),
    execution: execute.State,
    history: List(chat.Message(tool.Call)),
    recorded: cli.Trace,
  )
}

@target(javascript)
pub fn start(input, config: config.Config) {
  use started <- system.then(cli.initialize(input, config))
  case started {
    Error(reason) -> system.Done(Error(reason))
    Ok(#(session, execution)) -> {
      use id <- system.map(traces.new_id(session.config.started))
      Ok(Agent(session, execution, [], cli.start_trace(id, session)))
    }
  }
}

@target(erlang)
/// Overlay's model providers need the JavaScript runtime.
pub fn start(_input, _config: config.Config) {
  system.Done(Error(unavailable))
}

@target(erlang)
const unavailable = "Overlay needs the JavaScript runtime"

pub fn model_name(agent: Agent) {
  agent.session.llm.model
}

@target(javascript)
/// Add the person's message, then generate a reply.
pub fn ask(agent: Agent, text) {
  use at <- system.then(system.now())
  Agent(
    ..agent,
    history: [chat.UserMessage(text, []), ..agent.history],
    recorded: cli.prompted(agent.recorded, text, at),
  )
  |> generate
}

@target(javascript)
/// The model's next reply, streaming its text as standard output.
pub fn generate(agent: Agent) {
  use #(completion, recorded) <- system.map(cli.streamed_generation(
    agent.session,
    list.reverse(agent.history),
    agent.recorded,
    system.write_stdout,
  ))
  let agent = Agent(..agent, recorded:)
  case completion {
    Ok(completion) -> #(
      Ok(completion.tool_calls),
      Agent(..agent, history: [
        chat.from_completion(completion),
        ..agent.history
      ]),
    )
    Error(reason) -> #(Error(reason), agent)
  }
}

@target(erlang)
pub fn ask(agent: Agent, _text) {
  system.Done(#(Error(unavailable), agent))
}

@target(erlang)
pub fn generate(agent: Agent) {
  system.Done(#(Error(unavailable), agent))
}

/// The code a tool call runs, or its arguments.
pub fn code(call: tool.Call) {
  case agent.cast_tool_call(call.function.name, call.function.arguments) {
    Ok(agent.Run(code)) -> code
    _ -> utils.fields_to_json(call.function.arguments) |> json.to_string
  }
}

/// Run one tool call, returning its result and the effects it performed with
/// the policy's decision on each.
pub fn call(agent: Agent, call: tool.Call, index) {
  use #(returned, effects, execution, recorded) <- system.map(cli.call_recorded(
    agent.session,
    call,
    agent.execution,
    agent.recorded,
    index,
  ))
  let performed = {
    use #(label, input, decision, output) <- list.map(effects)
    shell.Performed(label, input, output, Some(decision))
  }
  let history = [cli.result_to_message(call.id, returned), ..agent.history]
  let result = result.map(returned, fn(returned) { returned.text })
  #(result, performed, Agent(..agent, execution:, recorded:, history:))
}

/// Keep the recorded trajectory, returning where it was saved.
pub fn save(agent: Agent) {
  cli.save(agent.session, agent.recorded)
}

pub fn export(agent: Agent, path) {
  cli.export(agent.session, agent.history, path)
}
