//// One real model request, one pure EYG program, one expected value.

import argv
import envoy
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state as interpreter
import eyg/interpreter/value
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug as parse_debug
import gleam/dict
import gleam/dynamic/decode
import gleam/fetch
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/web/prompt
import overlay/web/state
import simplifile

pub const fibonacci = "Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer."

/// Parse and type-check before evaluating. There is no effect handler.
pub fn evaluate(code: String) -> Result(interpreter.Value(Nil), String) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parse_debug.describe),
  )
  let source = ir.map_annotation(source, fn(_) { Nil })
  let context = infer.pure()
  let context = infer.Context(..context, env: [#("context", t.record([]))])
  let analysis = infer.check_with_references(context, dict.new(), source)
  case infer.all_errors(analysis) {
    [] ->
      expression.execute(source, [#("context", value.unit())])
      |> result.map_error(fn(debug) { simple_debug.describe(debug.0) })
    errors ->
      errors
      |> list.map(fn(error) { type_debug.reason(error.1) })
      |> string.join("\n")
      |> Error
  }
}

/// Tool arguments are the submitted program; prose is never graded.
pub fn program(
  completion: chat.Completion(tool.Call),
) -> Result(String, String) {
  case completion.tool_calls {
    [tool.Call(function: tool.FunctionCall("run", arguments), ..)] ->
      decode.run(
        utils.fields_to_dynamic(arguments),
        decode.field("code", decode.string, decode.success),
      )
      |> result.replace_error("run requires a code string")
    _ -> Error("expected exactly one run tool call")
  }
}

pub fn check(
  code: String,
  expected: interpreter.Value(Nil),
) -> Result(Nil, String) {
  use actual <- result.try(evaluate(code))
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(
        "expected "
        <> simple_debug.inspect(expected)
        <> ", got "
        <> simple_debug.inspect(actual),
      )
  }
}

fn configuration(description) {
  case string.split_once(description, ":") {
    Ok(#("ollama", model)) ->
      envoy.get("OLLAMA_API_KEY")
      |> result.replace_error("OLLAMA_API_KEY is required")
      |> result.map(fn(key) { #(ollama.cloud(key), model) })
    Ok(#("ollama-local", model)) -> Ok(#(ollama.local(), model))
    _ -> Error("use ollama:<model> or ollama-local:<model>")
  }
}

fn request(description, root) {
  use #(config, model) <- result.try(configuration(description))
  use syntax <- result.try(read(root <> "/guides/syntax.md"))
  use builtins <- result.map(read(root <> "/guides/builtins_reference.md"))
  ollama.completion_request(
    config,
    model,
    prompt.pure(syntax, builtins),
    [chat.UserMessage(fibonacci, [])],
    [state.spec()],
  )
}

fn read(path) {
  simplifile.read(path)
  |> result.replace_error("cannot read " <> path)
}

pub fn main() {
  let request = case argv.load().arguments {
    [model] -> request(model, "../..")
    [model, root] -> request(model, root)
    _ ->
      Error(
        "usage: gleam run -m overlay/eval/pure -- ollama:<model> [repo-root]",
      )
  }
  case request {
    Error(reason) -> promise.resolve(finish(Error(reason)))
    Ok(request) -> {
      use response <- promise.map(
        fetch.send_bits(request) |> promise.try_await(fetch.read_text_body),
      )
      let result = {
        use response <- result.try(result.map_error(response, string.inspect))
        use _ <- result.try(case response.status {
          200 -> Ok(Nil)
          status -> Error("provider returned HTTP " <> int.to_string(status))
        })
        use completion <- result.try(
          json.parse(
            response.body,
            decode.field("message", ollama.message_decoder(), decode.success),
          )
          |> result.replace_error("invalid model response"),
        )
        use code <- result.try(program(completion))
        io.println(code)
        check(code, value.Integer(17_710))
      }
      finish(result)
    }
  }
}

fn finish(result) {
  case result {
    Ok(Nil) -> io.println("PASS: Fibonacci sum = 17710")
    Error(reason) -> {
      io.println_error("FAIL: " <> reason)
      exit_code(1)
    }
  }
}

@external(javascript, "./process.mjs", "exitCode")
fn exit_code(code: Int) -> Nil
