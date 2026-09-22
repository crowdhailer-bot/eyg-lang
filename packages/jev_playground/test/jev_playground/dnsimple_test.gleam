import eyg/interpreter/value as v
import eyg/parser
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/dnsimple
import jev_playground/environment
import jev_playground/library
import jev_playground/options
import jev_playground/packages
import jev_playground/run
import morph/editable as e
import multiformats/cid/v1
import simplifile

fn source() {
  let assert Ok(text) = simplifile.read(dnsimple.context_path)
  let assert Ok(source) = library.parse(text)
  source
}

fn run(code) {
  let assert Ok(environment) = library.context(source(), environment.browser())
  let assert Ok(tree) = parser.all_from_string(code)
  let program = e.to_annotated(e.from_annotated(tree), [])
  run.evaluate_handled(
    program,
    environment,
    dnsimple.fixture(),
    dnsimple.handle,
  )
}

fn value(code) {
  let assert Ok(#(value, _)) = run(code)
  value
}

pub fn the_context_is_the_one_shared_to_the_hub_test() {
  assert v1.to_string(library.content_id(source(), packages.sha256))
    == dnsimple.context_id
}

pub fn domains_are_listed_test() {
  assert value("context.domain_names({})")
    == dnsimple.strings([
      "lovelace.dev", "analytical.engineering", "notes.garden", "babbage.org",
    ])
  assert value("context.count(context.domain_names({}))") == v.Integer(4)
  assert value("context.account({}).email") == v.String("ada@lovelace.dev")
}

pub fn records_are_read_test() {
  assert value("context.count(context.records(\"lovelace.dev\"))")
    == v.Integer(7)
  assert value("context.record_values(\"lovelace.dev\", \"A\")")
    == dnsimple.strings(["93.184.215.14", "93.184.215.15", "198.51.100.1"])
  assert value(
      "context.count(context.records_of_type(\"analytical.engineering\", \"MX\"))",
    )
    == v.Integer(2)
}

pub fn the_registrar_is_asked_test() {
  assert value("context.is_available(\"jev-rocks.com\")") == v.true()
  assert value("context.is_available(\"lovelace.dev\")") == v.false()
  assert value("context.count(context.name_servers(\"notes.garden\"))")
    == v.Integer(4)
  assert value("context.without_auto_renew({})")
    == dnsimple.strings([
      "analytical.engineering",
      "notes.garden",
      "babbage.org",
    ])
  assert value("context.expiring_before(\"2027-06-01\")")
    == dnsimple.strings(["lovelace.dev", "analytical.engineering"])
  assert value("context.domain(\"notes.garden\").expires_on")
    == v.String("2028-01-02")
}

pub fn lists_compose_test() {
  assert value(
      "context.sum(context.map(context.domain_names({}), (name) -> { context.count(context.records(name)) }))",
    )
    == v.Integer(14)
  assert value(
      "context.count(context.flatten(context.map(context.domain_names({}), context.records)))",
    )
    == v.Integer(14)
}

pub fn records_are_changed_test() {
  let assert Ok(#(_, account)) =
    run("context.add_record(\"notes.garden\", \"www\", \"A\", \"203.0.113.7\")")
  let assert Ok(domain) = dnsimple.find_domain(account, "notes.garden")
  assert list.any(domain.records, fn(r) {
    r.name == "www" && r.type_ == "A" && r.content == "203.0.113.7"
  })
  let assert Ok(#(removed, account)) =
    run("context.remove_record(\"lovelace.dev\", \"old\", \"TXT\")")
  assert removed == v.Integer(1)
  let assert Ok(domain) = dnsimple.find_domain(account, "lovelace.dev")
  assert !list.any(domain.records, fn(r) { r.name == "old" })
  let assert Ok(#(changed, account)) =
    run(
      "context.change_record(\"lovelace.dev\", \"api\", \"A\", \"198.51.100.4\")",
    )
  assert changed == v.Integer(1)
  let assert Ok(domain) = dnsimple.find_domain(account, "lovelace.dev")
  assert list.any(domain.records, fn(r) {
    r.name == "api" && r.content == "198.51.100.4"
  })
}

pub fn auto_renew_is_changed_test() {
  let assert Ok(#(_, account)) =
    run("context.enable_auto_renew(\"notes.garden\")")
  let assert Ok(domain) = dnsimple.find_domain(account, "notes.garden")
  assert domain.auto_renew
}

fn agent(code, effects) {
  let assert Ok(environment) = library.context(source(), environment.browser())
  let code = case code {
    "?" -> "todo"
    code -> code
  }
  let assert Ok(tree) = parser.all_from_string(code)
  let config =
    options.Config(..options.default_config(), focus_holes: True, effects:)
  agent.new("", action.todo_holes(e.from_annotated(tree)), environment, config)
}

pub fn effects_can_be_hidden_test() {
  let hidden =
    agent.options(agent("?", options.NoEffects)) |> list.map(options.key)
  assert !list.contains(hidden, "perform Print")
  let shown =
    agent.options(agent("?", options.EffectSignatures)) |> list.map(options.key)
  assert list.contains(shown, "perform Print")
}

pub fn the_effects_of_each_call_can_be_shown_test() {
  let program = "context.count(context.records(\"lovelace.dev\"))"
  let state = fn(effects) {
    json.to_string(agent.state(agent(program, effects)))
  }
  assert string.contains(
    state(options.EffectNodes),
    "context.records(\\\"lovelace.dev\\\") performs DNSimple",
  )
  assert !string.contains(state(options.EffectSignatures), "effects_performed")
}

pub fn the_readme_examples_have_their_strings_as_holes_test() {
  let assert Ok(environment) = library.context(source(), environment.browser())
  let assert Some(readme) = environment.context_readme(environment)
  let assert [first, second] = options.readme_examples(readme)
  assert first == "context.count(context.records(todo))"
  assert string.starts_with(second, "context.sum(context.map(")
}

pub fn compounds_are_built_from_the_context_test() {
  let keys = fn(strategy) {
    let assert Ok(environment) =
      library.context(source(), environment.browser())
    let config =
      options.Config(
        ..options.default_config(),
        focus_holes: True,
        context_compounds: strategy,
      )
    agent.new("", e.Vacant, environment, config)
    |> agent.options
    |> list.map(options.key)
  }
  assert list.contains(keys(options.ContextCalls), "context.domain_names({})")
  assert list.contains(
    keys(options.ContextBareCalls),
    "call context.domain_names(?)",
  )
  assert list.contains(
    keys(options.ContextChains),
    "context.count(context.domain_names({}))",
  )
  assert list.contains(
    keys(options.ContextExamples),
    "example context.count(context.records(?))",
  )
  assert !list.contains(
    keys(options.NoContextCompounds),
    "context.domain_names({})",
  )
}

pub fn requests_can_be_answered_over_http_test() {
  let #(status, body, _) =
    dnsimple.respond(dnsimple.fixture(), "GET", "/v2/whoami", <<>>)
  assert status == 200
  let assert Ok(text) = bit_array.to_string(body)
  assert string.contains(text, "ada@lovelace.dev")
}

pub fn arguments_of_context_functions_are_named_test() {
  let state =
    agent("context.change_record(todo, todo, todo, todo)", options.NoEffects)
    |> agent.state
    |> json.to_string
  assert string.contains(
    state,
    "argument 1 of 4, `domain`, to context.change_record",
  )
}

pub fn context_functions_are_offered_where_a_function_is_expected_test() {
  let keys =
    agent("context.map(context.domain_names({}), todo)", options.NoEffects)
    |> agent.options
    |> list.map(options.key)
  assert list.contains(keys, "context.records")
  assert list.contains(keys, "context.name_servers")
}

pub fn a_missing_domain_fails_with_the_message_of_the_api_test() {
  let assert Error(reason) = run("context.records(\"lovelace.com\")")
  assert string.contains(reason, "Zone `lovelace.com` not found")
}
