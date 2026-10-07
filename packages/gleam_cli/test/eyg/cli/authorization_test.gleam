import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/overlay
import eyg/hub/cache
import eyg/interpreter/value
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/execute
import loam/platform/computer
import loam/sandbox
import loam/sandbox/fs
import loam/source
import overlay/config
import overlay/llm/provider/ollama
import overlay/policy
import simplifile
import touch_grass/interface

fn state() {
  execute.State(helpers.config.client.origin, cache.empty())
}

fn files() {
  let root = "../../eyg_packages/authorization"
  let assert Ok(names) = simplifile.read_directory(root)
  list.fold(names, sandbox.sandbox(), fn(env, name) {
    let assert Ok(code) = simplifile.read(root <> "/" <> name)
    sandbox.with_file(env, "/eyg_packages/authorization/" <> name, code)
  })
}

fn evaluate(code, input, env) {
  let assert Ok(source) = source.parse_input(code, input)
  let assert #(sandbox.Returned(#(Ok(#(Some(value), _)), _)), env) =
    execute.block(source, [], state()) |> sandbox.run(env)
  #(value, env)
}

pub fn every_authorization_tutorial_example_executes_test() {
  let assert Ok(document) = simplifile.read("../../guides/authorization.md")
  let assert [_, ..blocks] = string.split(document, "```eyg\n")
  assert list.length(blocks) == 9
  list.each(blocks, fn(block) {
    let assert Ok(#(code, _)) = string.split_once(block, "```")
    let assert Ok(parsed) =
      source.parse_input(code, source.File("/guides/authorization.md"))
    let assert #(sandbox.Returned(#(_, _, errors)), _) =
      check.check_from(parsed, "/", infer.pure(), state())
      |> sandbox.run(files())
    assert errors == []
    let #(result, _) =
      evaluate(code, source.File("/guides/authorization.md"), files())
    assert result == value.Tagged("True", value.unit())
  })
}

pub fn example_config_conforms_to_the_cli_policy_type_test() {
  let path = "/examples/authorization/overlay.eyg"
  let assert Ok(code) = simplifile.read("../.." <> path)
  let assert Ok(source) = source.parse_input(code, source.File(path))
  let context =
    infer.pure()
    |> infer.with_effects(interface.types(computer.effects()))
  let #(expected, bindings) =
    config.type_(overlay.policy_rules(), context.level, context.bindings)
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
  let env = files() |> sandbox.with_env("HOME", "/home/alice")
  let assert #(sandbox.Returned(#(_, _, errors)), _) =
    check.check_from(source, "/", context, state()) |> sandbox.run(env)
  assert errors == []
  let #(raw, _) = evaluate(code, source.File(path), env)
  let assert Ok(_) = config.cast(raw, overlay.policy_rules())
  let assert #(sandbox.Exited(1), missing_home) =
    execute.block(source, [], state()) |> sandbox.run(files())
  assert missing_home.stderr == ["HOME is required\n"]
}

fn test_policy() {
  let code =
    "let {make} = import \"../eyg_packages/authorization/overlay.eyg\"
     make(@{
       fact Home({tenant: \"acme\", actor: \"alice\", path: \"/home/alice\"}),
       fact AllowedOrigin({tenant: \"acme\", actor: \"alice\", scheme: HTTPS({}), host: \"api.example.com\", port: None({})})
     }, {tenant: \"acme\", actor: \"alice\"})"
  let #(raw, _) = evaluate(code, source.File("/guides/example.eyg"), files())
  let assert Ok(policy) = policy.decode_policy(overlay.policy_rules(), raw)
  policy
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

pub fn denied_writes_do_not_reach_the_filesystem_test() {
  let env =
    sandbox.sandbox()
    |> sandbox.with_directory("/home/alice")
    |> sandbox.with_file("/private/secret", "unchanged")
  let code =
    "let allowed = perform WriteFile({path: \"/home/alice/./report\", contents: !string_to_binary(\"report\")})
     let denied = perform WriteFile({path: \"/home/alice/../../private/secret\", contents: !string_to_binary(\"bad\")})
     {allowed, denied}"
  let assert #(sandbox.Returned(#(Ok(_), _)), env) =
    overlay.execute_call(call(code), "/", state(), test_policy(), value.unit())
    |> sandbox.run(env)
  assert fs.read(env.file_system, "/home/alice/report") == Ok("report")
  assert fs.read(env.file_system, "/private/secret") == Ok("unchanged")
}

pub fn only_permitted_get_requests_reach_the_network_test() {
  let env =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, count) {
        #(Ok(response.Response(200, [], <<"ok":utf8>>)), count + 1)
      },
      0,
    )
  let code =
    "let request = {method: GET({}), scheme: HTTPS({}), host: \"api.example.com\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")}
     let allowed = perform Fetch(request)
     let post = perform Fetch({method: POST({}), ..request})
     let other = perform Fetch({host: \"evil.example\", ..request})
     {allowed, post, other}"
  let assert #(sandbox.Returned(#(Ok(_), _)), env) =
    overlay.execute_call(call(code), "/", state(), test_policy(), value.unit())
    |> sandbox.run(env)
  assert env.network_state == 1
}
