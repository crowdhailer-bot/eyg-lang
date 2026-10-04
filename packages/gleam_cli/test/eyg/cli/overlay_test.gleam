import eyg/analysis/type_/isomorphic as t
import eyg/cli/helpers
import eyg/cli/overlay
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/value
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/execute
import loam/platform/computer
import loam/sandbox
import loam/sandbox/fs
import loam/source
import overlay/llm/chat
import overlay/llm/provider
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
      session("/", policy_with([#("standard_out", stdout_policy)])),
      call(code),
      state(),
    )
    |> sandbox.run(sandbox.sandbox())
  #(result, sandbox)
}

fn state() {
  overlay.Runtime(
    execute.State(helpers.config.client.origin, cache.empty()),
    policy_state: None,
  )
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
      session("/project", policy_with(policies)),
      call("import \"./secret.eyg\""),
      state(),
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
      session("/project", policy_with([])),
      call("import \"./lib.eyg\""),
      state(),
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
  let fields =
    list.fold(overrides, dict.from_list(fields), fn(fields, override) {
      dict.insert(fields, override.0, evaluate(override.1))
    })
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(policy) = policy.decode(value.Record(fields), labels)
  policy
}

pub fn effect_without_policy_field_is_refused_test() {
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(policy) = policy.decode(value.Record(dict.new()), labels)
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(session("/", policy), call("perform Now({})"), state())
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
      session("/", policy_with([#("now", "(_) -> { Allow({}) }")])),
      call("perform Now({})"),
      state(),
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Error(reason) = result
  assert string.contains(
    reason,
    "policy for Now failed: a policy function must return Pass(value), Mock(value) or Ask({question, denied})",
  )
}

pub fn policy_sees_absolute_paths_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_cwd("/project")
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      session(
        "/project",
        policy_with([
          #("read_file", "(request) -> { Mock(Error(request.path)) }"),
        ]),
      ),
      call(
        "perform ReadFile({path: \"./docs/../a.txt\", offset: 0, limit: 10})",
      ),
      state(),
    )
    |> sandbox.run(sandbox)
  assert result == Ok(tool.Return("Error(\"/project/a.txt\")", []))
}

pub fn abort_is_reported_test() {
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(
      session("/", policy_with([])),
      call("perform Abort(\"stop here\")"),
      state(),
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Error(reason) = result
  assert string.contains(reason, "Aborted with reason: \"stop here\"")
}

fn session(cwd, policy) {
  overlay.Session(
    llm: provider.Llm(provider.Ollama(ollama.local()), "model"),
    provider_context: provider.Context("", []),
    cwd:,
    policy:,
    context: value.unit(),
    context_type: t.unit,
    audit: None,
    context_policy: None,
  )
}

pub fn type_errors_are_returned_without_running_test() {
  let assert #(sandbox.Returned(#(result, _)), sandbox) =
    overlay.execute_call(
      session("/", policy_with([])),
      call("let _ = perform StandardOut(\"ran\") !int_add(1, \"2\")"),
      state(),
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Error(reason) = result
  assert string.contains(reason, "type") || string.contains(reason, "String")
  assert sandbox.stdout == []
}

pub fn context_type_is_used_test() {
  let session =
    overlay.Session(
      ..session("/", policy_with([])),
      context: value.Record(dict.from_list([#("count", value.Integer(2))])),
      context_type: t.record([#("count", t.Integer)]),
    )
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(session, call("!int_add(context.count, 1)"), state())
    |> sandbox.run(sandbox.sandbox())
  assert result == Ok(tool.Return("3", []))
}

fn ask_session() {
  session(
    "/",
    policy_with([
      #(
        "now",
        "(_) -> { Ask({question: \"Can the agent read the time?\", denied: 0}) }",
      ),
    ]),
  )
}

pub fn ask_allowed_test() {
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(ask_session(), call("perform Now({})"), state())
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_now(42)
      |> sandbox.with_prompt_response(Ok("y")),
    )
  assert result == Ok(tool.Return("42", []))
}

pub fn ask_denied_test() {
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(ask_session(), call("perform Now({})"), state())
    |> sandbox.run(
      sandbox.sandbox()
      |> sandbox.with_now(42)
      |> sandbox.with_prompt_response(Ok("n")),
    )
  assert result == Ok(tool.Return("0", []))
}

pub fn audit_is_called_for_every_effect_test() {
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(only_now) =
    policy.decode(
      value.Record(dict.from_list([#("now", evaluate("(x) -> { Pass(x) }"))])),
      labels,
    )
  let session =
    overlay.Session(
      ..session("/", only_now),
      audit: Some(evaluate(
        "(entry) -> {
          let line = !string_append(entry.effect, !string_append(\" \", entry.decision))
          perform AppendFile({path: \"/audit.log\", contents: !string_to_binary(!string_append(line, \"\\n\"))})
        }",
      )),
    )
  let assert #(sandbox.Returned(#(Error(_), _)), sandbox) =
    overlay.execute_call(
      session,
      call("let _ = perform Now({}) perform StandardIn({})"),
      state(),
    )
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(1))
  let assert Ok(log) = fs.read(sandbox.file_system, "/audit.log")
  assert log == "Now pass\nStandardIn refused\n"
}

pub fn context_policy_applies_to_context_code_test() {
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(nothing) = policy.decode(value.Record(dict.new()), labels)
  let assert Ok(only_now) =
    policy.decode(
      value.Record(dict.from_list([#("now", evaluate("(x) -> { Pass(x) }"))])),
      labels,
    )
  let assert Ok(source) =
    source.parse("(_) -> { perform Now({}) }", source.Disk("/project/time.eyg"))
  let assert Ok(time) = block.execute(source, []) |> result.map(fn(r) { r.0 })
  let assert Some(time) = time
  let session =
    overlay.Session(
      ..session("/", nothing),
      context: time,
      context_type: t.Fun(
        t.unit,
        t.EffectExtend("Now", #(t.unit, t.Integer), t.Empty),
        t.Integer,
      ),
      context_policy: Some(only_now),
    )
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(session, call("context({})"), state())
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(7))
  assert result == Ok(tool.Return("7", []))
  let assert #(sandbox.Returned(#(Error(reason), _)), _) =
    overlay.execute_call(session, call("perform Now({})"), state())
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(7))
  assert string.contains(reason, "the Now effect is not permitted")
}

pub fn untrusted_reference_is_not_loaded_test() {
  let session =
    session(
      "/",
      policy_with([
        #(
          "reference",
          "(ref) -> { match !equal(ref, \"@standard\") { True(_) -> { Pass(ref) } False(_) -> { Mock(\"untrusted\") } } }",
        ),
      ]),
    )
  let assert #(sandbox.Returned(#(Error(reason), _)), _) =
    overlay.execute_call(session, call("@evil"), state())
    |> sandbox.run(sandbox.sandbox())
  assert string.contains(reason, "reference @evil denied by policy: untrusted")
}

pub fn stateful_policy_allows_once_test() {
  let labels = list.map(computer.effects(), fn(effect) { effect.name })
  let assert Ok(once) =
    policy.decode(
      value.Record(
        dict.from_list([
          #(
            "now",
            evaluate(
              "(lift, used) -> { match used { True(_) -> { {decision: Mock(0), state: used} } False(_) -> { {decision: Pass(lift), state: True({})} } } }",
            ),
          ),
        ]),
      ),
      labels,
    )
  let runtime = overlay.Runtime(..state(), policy_state: Some(value.false()))
  let assert #(sandbox.Returned(#(result, runtime)), _) =
    overlay.execute_call(session("/", once), call("perform Now({})"), runtime)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(5))
  assert result == Ok(tool.Return("5", []))
  assert runtime.policy_state == Some(value.true())
  let assert #(sandbox.Returned(#(result, _)), _) =
    overlay.execute_call(session("/", once), call("perform Now({})"), runtime)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(5))
  assert result == Ok(tool.Return("0", []))
}
