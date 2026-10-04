//// The main tool available to an Overlay agent.
//// Behaviour matches the run CLI command, top level effects are executed.

import castor
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/tool

pub const name: String = "run"

pub const description: String = "Run an EYG program and return its final expression as the result. Top-level effects are allowed. Print is for extra output and returns {}, so leave the requested answer as the final expression."

pub fn parameters() -> List(#(String, castor.Ref(castor.Schema), Bool)) {
  [castor.field("code", castor.string())]
}

pub fn spec() -> tool.Tool {
  tool.Tool(name, description, parameters())
}

pub fn cast(
  arguments: Dict(String, utils.Any),
) -> Result(String, List(decode.DecodeError)) {
  let arguments = utils.fields_to_dynamic(arguments)
  let decoder = {
    decode.field("code", decode.string, decode.success)
  }
  decode.run(arguments, decoder)
}

/// The text returned to the agent, everything printed before the final result of the program.
/// Output is held newest first.
pub fn report(output: List(String), result: String) -> String {
  case list.reverse(output) {
    [] -> result
    printed -> "Output:\n" <> string.concat(printed) <> "\nResult:\n" <> result
  }
}
