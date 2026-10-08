import gleam/javascript/promise
import gleam/string
import gleeunit
import opencode_plugin.{type Config}
import opencode_plugin/policy
import simplifile

pub fn main() {
  gleeunit.main()
}

const fixtures = "test/fixtures"

fn directory() {
  let assert Ok(cwd) = simplifile.current_directory()
  cwd <> "/" <> fixtures
}

fn with_config(then: fn(Config) -> promise.Promise(Nil)) {
  use config <- promise.await(opencode_plugin.load(fixtures <> "/read_only.eyg"))
  let assert Ok(config) = config
  then(config)
}

fn run(code, policy, config) {
  opencode_plugin.run(
    code,
    policy,
    opencode_plugin.config_context(config),
    directory(),
    [],
  )
}

pub fn field_names_test() {
  assert policy.field("ReadFile") == "read_file"
  assert policy.field("CWD") == "cwd"
  assert policy.field("WebFetch") == "web_fetch"
  assert policy.field("Task") == "task"
  assert policy.field("DecodeJSON") == "decode_json"
}

pub fn context_and_pure_code_test() {
  use config <- with_config()
  assert opencode_plugin.config_readme(config) == "hello"
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run("context.readme", policy, config))
  assert opencode_plugin.report_ok(report)
  assert opencode_plugin.report_text(report) == "hello"
}

pub fn passed_effect_is_performed_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let code =
    "match perform ReadFile({path: \"notes.md\", offset: 0, limit: 100}) {
      Ok(bytes) -> { !string_from_binary(bytes) }
      Error(reason) -> { Error(reason) }
    }"
  use report <- promise.map(run(code, policy, config))
  assert opencode_plugin.report_text(report) == "Ok(\"# notes\\n\")"
}

pub fn mocked_effect_is_not_performed_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let code =
    "perform WriteFile({path: \"out.txt\", contents: !string_to_binary(\"x\")})"
  use report <- promise.map(run(code, policy, config))
  assert opencode_plugin.report_text(report) == "Error(\"read only\")"
  assert simplifile.is_file(fixtures <> "/out.txt") == Ok(False)
}

pub fn effect_without_field_is_unavailable_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run("perform Env(\"HOME\")", policy, config))
  assert !opencode_plugin.report_ok(report)
  assert string.contains(
    opencode_plugin.report_text(report),
    "The effect Env is not allowed by your policy, it has no `env` gate.",
  )
}

pub fn standard_out_is_captured_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run(
    "let _ = perform StandardOut(\"hi\")
    5",
    policy,
    config,
  ))
  assert opencode_plugin.report_text(report) == "Output:\nhi\nResult:\n5"
}

pub fn subagent_policy_restricts_parent_test() {
  use config <- with_config()
  let parent = opencode_plugin.config_policy(config)
  use child <- promise.await(opencode_plugin.evaluate(
    fixtures <> "/subagent.eyg",
  ))
  let assert Ok(child) = child
  let assert Ok(policy) = opencode_plugin.restrict(parent, child)
  assert opencode_plugin.fields(policy) == ["read_file"]
  let read = fn(path) {
    "match perform ReadFile({path: \"" <> path <> "\", offset: 0, limit: 100}) {
      Ok(_) -> { \"read\" }
      Error(reason) -> { reason }
    }"
  }
  use secret <- promise.await(run(read("secret.txt"), policy, config))
  assert opencode_plugin.report_text(secret) == "only markdown"
  use notes <- promise.await(run(read("notes.md"), policy, config))
  assert opencode_plugin.report_text(notes) == "read"
  use listing <- promise.map(run("perform ReadDirectory(\".\")", policy, config))
  assert !opencode_plugin.report_ok(listing)
}

pub fn agent_policy_replaces_parent_test() {
  use config <- with_config()
  let assert Ok(policy) = opencode_plugin.agent_policy(config, "writer")
  assert opencode_plugin.fields(policy) == ["write_file"]
  assert opencode_plugin.agent_policy(config, "other") == Error(Nil)
  promise.resolve(Nil)
}

pub fn host_effect_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let task =
    opencode_plugin.host(
      "Task",
      "{prompt: String}",
      "String",
      unsafe(fn(input, _raw) { promise.resolve(input) }),
    )
  use report <- promise.map(
    opencode_plugin.run(
      "perform Task({prompt: \"go\"})",
      policy,
      opencode_plugin.config_context(config),
      directory(),
      [task],
    ),
  )
  assert opencode_plugin.report_text(report) == "Ok({prompt: \"go\"})"
}

@external(javascript, "./opencode_plugin_ffi.mjs", "identity")
fn unsafe(x: a) -> b
