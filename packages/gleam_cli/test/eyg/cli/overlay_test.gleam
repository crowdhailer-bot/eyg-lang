import eyg/cli/helpers
import eyg/cli/overlay
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/value
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/execute
import loam/platform/computer
import loam/sandbox
import loam/source
import overlay/llm/chat
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/policy

pub fn stdout_is_returned_and_still_written_to_the_terminal_test() {
  let #(result, sandbox) =
    run(
      "let _ = perform StandardOut(\"first\")
     let _ = perform StandardOut(\"second\\n\") 5",
      "(text) -> { Pass(text) }",
    )
  assert overlay.result_to_message("call", result)
    == chat.ToolResultMessage("call", "Output:\nfirstsecond\n\nResult:\n5", [])
  assert list.reverse(sandbox.stdout) == ["first", "second\n"]
}

fn run(code, stdout_policy) {
  let assert #(sandbox.Returned(#(result, _)), sandbox) =
    overlay.execute_call(
      call(code),
      "/",
      state(),
      policy_with([#("standard_out", stdout_policy)]),
      value.unit(),
    )
    |> sandbox.run(sandbox.sandbox())
  #(result, sandbox)
}

fn state() {
  execute.State(helpers.config.client.origin, cache.empty())
}

fn call(code) {
  let encoded =
    json.object([
      #(
        "function",
        json.object([
          #("name", json.string("run")),
          #("arguments", json.object([#("code", json.string(code))])),
        ]),
      ),
    ])
  let assert Ok(call) =
    json.parse(json.to_string(encoded), ollama.tool_call_decoder())
  call.function
}

fn evaluate(code) {
  let assert Ok(source) = source.parse_input(code, source.Stdin)
  let assert Ok(#(Some(value), _)) = block.execute(source, [])
  value
}

pub fn relative_import_is_checked_by_read_file_policy_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project")
    |> sandbox.with_file("/project/secret.eyg", "\"hidden\"")
  let policies = [
    #("read_file", "(_) -> { Mock(Error(\"denied\")) }"),
  ]
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      call("import \"./secret.eyg\""),
      "/project",
      state(),
      policy_with(policies),
      value.unit(),
    )
    |> sandbox.run(sandbox)
  let assert Error(reason) = result
  assert !string.contains(reason, "hidden")
  assert string.contains(reason, "denied")
}

pub fn relative_import_is_allowed_by_read_file_policy_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project")
    |> sandbox.with_file("/project/lib.eyg", "\"shared\"")
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      call("import \"./lib.eyg\""),
      "/project",
      state(),
      policy_with([]),
      value.unit(),
    )
    |> sandbox.run(sandbox)
  assert result == Ok(tool.Return("\"shared\"", []))
}

fn policy_with(overrides) {
  let pass = evaluate("(value) -> { Pass(value) }")
  let fields =
    list.map(
      [
        "append_file", "create_key", "cwd", "delete_file", "env", "fetch",
        "make_directory", "now", "random", "read_directory", "read_file", "sign",
        "sleep", "standard_error", "standard_in", "standard_out", "write_file",
      ],
      fn(name) {
        case list.key_find(overrides, name) {
          Ok(code) -> #(name, evaluate(code))
          Error(Nil) -> #(name, pass)
        }
      },
    )
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(policy) =
    policy.decode(value.Record(dict.from_list(fields)), labels)
  policy
}

pub fn effect_without_policy_field_is_refused_test() {
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(policy) = policy.decode(value.Record(dict.new()), labels)
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      call("perform Now({})"),
      "/",
      state(),
      policy,
      value.unit(),
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Error(reason) = result
  assert string.contains(
    reason,
    "the Now effect is not permitted, the policy has no `now` field",
  )
}

pub fn failing_policy_is_reported_test() {
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      call("perform Now({})"),
      "/",
      state(),
      policy_with([#("now", "(_) -> { Allow({}) }")]),
      value.unit(),
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Error(reason) = result
  assert string.contains(
    reason,
    "policy for Now failed: a policy function must return Pass(value) or Mock(value)",
  )
}

pub fn policy_sees_absolute_paths_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_cwd("/project")
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      call(
        "perform ReadFile({path: \"./docs/../a.txt\", offset: 0, limit: 10})",
      ),
      "/project",
      state(),
      policy_with([#("read_file", "(request) -> { Mock(Error(request.path)) }")]),
      value.unit(),
    )
    |> sandbox.run(sandbox)
  assert result == Ok(tool.Return("Error(\"/project/a.txt\")", []))
}
