//// Overlay does not know what it is embedded in. These tests stand in for an
//// application that embeds it: a counter with one effect of its own and no
//// browser anywhere.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/dict
import gleam/string
import oas/generator/utils
import overlay/helpers.{new_reader, test_origin}
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/environment.{Environment}
import overlay/web/environment/browser
import overlay/web/provider_setup
import overlay/web/state.{State}
import pal/system

fn counting(count: Int, label: String, lift) {
  case label {
    "Bump" -> {
      let count = count + 1
      #(count, environment.Working(system.Done(v.Integer(count))))
    }
    "Boom" -> #(count, environment.Stopped("the counter fell over"))
    "Announce" -> #(
      count,
      environment.Working(
        system.Alert("counting", fn() { system.Done(v.unit()) }),
      ),
    )
    _ -> #(count, environment.Unknown(break.UnhandledEffect(label, lift)))
  }
}

fn counter() {
  Environment(
    host: 0,
    handler: counting,
    briefing: "You are looking after a counter.",
    effects: [
      #("Bump", #(t.unit, t.Integer)),
      #("Announce", #(t.unit, t.unit)),
    ],
    scope: [#("step", v.Integer(10))],
  )
}

fn init() {
  let config = state.Config(origin: test_origin(), environment: counter())
  let #(state, _) = state.init(config)
  let #(state, _) =
    state.update(
      state,
      state.ProviderSetupMessage(provider_setup.SessionSettingsLoaded(
        "ollama",
        "qwen3.5:397b",
        "test-key",
      )),
    )
  state
}

fn running(code) {
  let call =
    tool.Call(
      id: "abc",
      function: tool.FunctionCall(
        name: "run",
        arguments: dict.from_list([#("code", utils.String(code))]),
      ),
    )
  let completion =
    chat.Completion(thinking: "", content: "", tool_calls: [call])
  let status =
    state.Streaming(
      reader: new_reader([], Ok(Nil)),
      completion:,
      remaining: <<>>,
    )
  State(..init(), status:)
}

pub fn an_effect_changes_the_application_state_test() {
  let code =
    "let a = perform Bump({})
let b = perform Bump({})
!int_add(a, b)"
  let #(state, _) =
    state.update(running(code), state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("abc", "3", [])]) == state.status
  assert 2 == state.environment.host
}

pub fn the_application_state_carries_between_tool_calls_test() {
  let #(state, _) =
    state.update(running("perform Bump({})"), state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("abc", "1", [])]) == state.status

  let completion =
    chat.Completion(thinking: "", content: "", tool_calls: [
      tool.Call(
        id: "def",
        function: tool.FunctionCall(
          name: "run",
          arguments: dict.from_list([
            #("code", utils.String("perform Bump({})")),
          ]),
        ),
      ),
    ])
  let status =
    state.Streaming(
      reader: new_reader([], Ok(Nil)),
      completion:,
      remaining: <<>>,
    )
  let state = State(..state, status:)
  let #(state, _) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("def", "2", [])]) == state.status
  assert 2 == state.environment.host
}

pub fn a_program_starts_with_the_environments_scope_in_hand_test() {
  let #(state, _) =
    state.update(
      running("!int_add(step, perform Bump({}))"),
      state.LlmStreamFinished(Ok(Nil)),
    )
  assert state.Asking([chat.ToolResultMessage("abc", "11", [])]) == state.status
}

pub fn a_stopped_effect_reports_its_reason_test() {
  let #(state, _) =
    state.update(running("perform Boom({})"), state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([
      chat.ToolResultMessage("abc", "the counter fell over", []),
    ])
    == state.status
}

pub fn an_effect_the_environment_does_not_have_is_unhandled_test() {
  let #(state, _) =
    state.update(running("perform Fetch({})"), state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([chat.ToolResultMessage(text:, ..)]) = state.status
  assert string.contains(text, "Fetch")
}

pub fn work_the_environment_hands_back_is_run_test() {
  let #(state, actions) =
    state.update(
      running("perform Announce({})"),
      state.LlmStreamFinished(Ok(Nil)),
    )
  let assert state.Executing(_) = state.status
  let assert [system.Alert("counting", resume:)] = actions
  let assert system.Done(message) = resume()
  let #(state, _) = state.update(state, message)
  assert state.Asking([chat.ToolResultMessage("abc", "{}", [])]) == state.status
}

pub fn the_system_prompt_is_written_from_the_environment_test() {
  let prompt = state.system_prompt(counter())
  assert string.contains(prompt, "You are looking after a counter.")
  assert string.contains(prompt, "- Bump({}) -> Integer")
  // nothing of the browser leaks in
  assert !string.contains(prompt, "Fetch")
  assert !string.contains(prompt, "DNSimple")
}

pub fn the_browser_prompt_still_describes_the_browser_test() {
  let prompt = state.system_prompt(browser.environment(test_origin()))
  assert string.contains(prompt, "eyg-syntax-guide.md")
  assert string.contains(prompt, "- Fetch(")
  assert string.contains(prompt, "DNSimple")
}
