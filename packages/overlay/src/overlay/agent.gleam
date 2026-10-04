//// The module for dealing with tool calls from an LLM
//// There is more than way to wire up an agent to user input.
//// User input is not the responsibility of this module and it handles the inner loop only.

import eyg/analysis/type_/binding/debug
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/tool
import overlay/tools/guide
import overlay/tools/run
import touch_grass/interface

/// Construct the system prompt for an agent
pub fn system_prompt(
  effects: List(interface.Interface(a, b)),
  readme: String,
) -> String {
  "You are an expert automation assistant.
You help users by executing EYG scripts to interact with the users system.
DO NOT guess any function of effects. Only use what you have seen explained and use the guide tool to learn more about writing EYG code.

ALWAYS use djot syntax for your responses.
DO NOT write code blocks in your responses unless explicitly asked.
All code execution uses the 'run' tool.
Every program has the variable context in scope, it is the module described in the Context section at the end of this prompt.

ALWAYS read the syntax guide, using the guide tool, before writing scripts.
Other guides are builtins and http-fetch.

This environment has the following effects

"
  |> string.append(
    effects
    |> list.map(describe_effect)
    |> string.join("\n"),
  )
  <> "

Remember to always use perform to call an effect.
Effects are checked by a policy set by the user. If an effect is denied report it to the user, DO NOT try to work around the policy.

# Context

"
  <> readme
}

/// A single line in the system prompt describing an effect, e.g.
/// `- Now({}) -> Int`
pub fn describe_effect(effect: interface.Interface(a, b)) -> String {
  let interface.Interface(name:, lift_type:, lower_type:, decode: _) = effect
  "- "
  <> name
  <> "("
  <> debug.mono(lift_type)
  <> ") -> "
  <> debug.mono(lower_type)
}

pub type ToolCall {
  Run(String)
  Guide(String)
}

pub type CastFailure {
  DecodeError(errors: List(decode.DecodeError))
  UnknownTool
}

pub fn describe_failure(
  failure: CastFailure,
  name: String,
  arguments: Dict(String, utils.Any),
) -> String {
  case failure {
    DecodeError(errors: _) -> {
      "Bad arguments for tool "
      <> name
      <> " arguments: "
      <> json.to_string(utils.any_to_json(utils.Object(arguments)))
    }
    UnknownTool -> {
      let message = "Failed to call tool `" <> name <> "` it is not setup."
      message
    }
  }
}

pub fn cast_tool_call(
  name: String,
  arguments: Dict(String, utils.Any),
) -> Result(ToolCall, CastFailure) {
  case name {
    "run" -> run.cast(arguments) |> to(Run)
    "guide" -> guide.cast(arguments) |> to(Guide)
    _ -> Error(UnknownTool)
  }
}

fn to(result, call) {
  case result {
    Ok(arguments) -> Ok(call(arguments))
    Error(reason) -> Error(DecodeError(reason))
  }
}

/// The tools available to every overlay agent.
pub fn tools() -> List(tool.Tool) {
  [run.spec(), guide.spec()]
}
