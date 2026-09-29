import eyg/analysis/type_/isomorphic as t
import eyg/embed/agent
import eyg/embed/shell
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama

fn new() {
  let llm = provider.Llm(provider.Ollama(ollama.local()), "test-model")
  agent.new(llm, agent.system_prompt("You count.", "Add(n) adds n.", "guide"))
}

fn counter() {
  shell.new([#("Add", #(t.Integer, t.Integer))])
}

fn add(total, _label, lift) {
  let assert v.Integer(n) = lift
  Ok(#(total + n, v.Integer(total + n)))
}

fn event(message) {
  json.object([#("message", json.object(message))]) |> json.to_string
}

fn call(code) {
  event([
    #("role", json.string("assistant")),
    #("content", json.string("")),
    #(
      "tool_calls",
      json.preprocessed_array([
        json.object([
          #(
            "function",
            json.object([
              #("name", json.string("run")),
              #("arguments", json.object([#("code", json.string(code))])),
            ]),
          ),
        ]),
      ]),
    ),
  ])
  |> bit_array.from_string
}

fn say(parts) {
  list.map(parts, fn(part) {
    event([#("role", json.string("assistant")), #("content", json.string(part))])
  })
  |> string.join("\n")
  |> bit_array.from_string
}

pub fn asking_sends_the_prompt_and_the_run_tool_test() {
  let #(agent, request) = agent.ask(new(), "count")
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "Add(n) adds n.")
  assert string.contains(body, "\"name\":\"run\"")
  assert agent.messages(agent) == [chat.UserMessage("count", [])]
}

pub fn code_the_model_asks_for_runs_in_the_shell_test() {
  let #(agent, _) = agent.ask(new(), "add two")
  let run = agent.run_in_shell(add)
  let assert agent.Continue(
    agent,
    #(shell, 2),
    [#("let n = perform Add(2)", "{}")],
    _,
  ) = agent.respond(agent, #(counter(), 0), call("let n = perform Add(2)"), run)
  let assert agent.Continue(_, #(_, 2), [#(_, "2")], _) =
    agent.respond(agent, #(shell, 2), call("n"), run)
}

pub fn a_type_error_is_reported_to_the_model_test() {
  let #(agent, _) = agent.ask(new(), "launch")
  let assert agent.Continue(agent, _, [#(_, report)], _) =
    agent.respond(
      agent,
      #(counter(), 0),
      call("perform Launch({})"),
      agent.run_in_shell(add),
    )
  assert report
    == "The code did not type check, nothing ran.\nline 1: missing row 'Launch'"
  let assert [_, _, chat.ToolResultMessage(text:, ..)] = agent.messages(agent)
  assert text == report
}

pub fn a_reply_without_tool_calls_answers_the_user_test() {
  let #(agent, _) = agent.ask(new(), "hello")
  let assert agent.Answered(_, 0, "Hello there") =
    agent.respond(agent, 0, say(["Hello", " there"]), fn(s, _) { #(s, "") })
  let assert agent.Answered(_, 0, "Hi") =
    agent.respond(agent, 0, <<say(["Hi"]):bits, "\n\n":utf8>>, fn(s, _) {
      #(s, "")
    })
}

pub fn an_agent_is_stopped_after_its_limit_test() {
  let #(agent, _) = agent.ask(new() |> agent.with_limit(1), "loop")
  let run = fn(s, _) { #(s, "{}") }
  let assert agent.Continue(agent, _, _, _) =
    agent.respond(agent, 0, call("1"), run)
  let assert agent.Failed(_, 0, "Stopped after 1 steps.") =
    agent.respond(agent, 0, call("1"), run)
}

pub fn runs_can_take_time_test() {
  let #(agent, _) = agent.ask(new(), "add")
  use step <- promise.map(
    agent.respond_async(agent, 0, call("1"), fn(s, code) {
      promise.resolve(#(s + 1, "ran " <> code))
    }),
  )
  let assert agent.Continue(_, 1, [#("1", "ran 1")], _) = step
}
