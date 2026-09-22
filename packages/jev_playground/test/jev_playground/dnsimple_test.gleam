import eyg/interpreter/value as v
import eyg/parser
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{None, Some}
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

// The context in scope as `context`, with the libraries a program may open,
// as an eval and the overlay page give them.
fn environment() {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(base) = library.environment(bundle, environment.browser())
  let assert Ok(environment) = library.context(source(), base)
  environment
}

fn run(code) {
  let environment = environment()
  let assert Ok(tree) =
    parser.all_from_string(environment.pin_packages(code, environment))
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

pub fn the_account_is_read_test() {
  assert value("context.whoami({}).account.email")
    == v.String("ada@lovelace.dev")
  assert value("@standard.list.length(context.list_domains({}))")
    == v.Integer(4)
  assert value("context.get_domain(\"notes.garden\").expires_at")
    == v.String("2028-01-02T00:00:00Z")
}

pub fn zone_records_are_read_test() {
  assert value(
      "@standard.list.length(context.list_zone_records(\"lovelace.dev\"))",
    )
    == v.Integer(7)
  assert value("context.get_zone_record(\"lovelace.dev\", 104).content")
    == v.String("198.51.100.1")
  assert value(
      "@standard.list.length(@standard.list.filter((record) -> { !equal(record.type, \"A\") }, context.list_zone_records(\"lovelace.dev\")))",
    )
    == v.Integer(3)
}

pub fn the_registrar_is_asked_test() {
  assert value("context.check_domain(\"jev-rocks.com\").available") == v.true()
  assert value("context.check_domain(\"lovelace.dev\").available") == v.false()
  assert value("context.get_domain_delegation(\"notes.garden\")")
    == dnsimple.strings(dnsimple.fixture().name_servers)
}

pub fn zone_records_are_changed_test() {
  let assert Ok(#(created, account)) =
    run(
      "context.create_zone_record(\"notes.garden\", {name: \"www\", type: \"A\", content: \"203.0.113.7\", ttl: 3600})",
    )
  let assert Ok(domain) = dnsimple.find_domain(account, "notes.garden")
  assert list.any(domain.records, fn(r) {
    r.name == "www" && r.type_ == "A" && r.content == "203.0.113.7"
  })
  assert created
    == dnsimple.record_value(dnsimple.Record(
      1000,
      "www",
      "A",
      "203.0.113.7",
      3600,
      None,
    ))

  let assert Ok(#(_, account)) =
    run(
      "context.update_zone_record(\"lovelace.dev\", 104, {name: \"api\", type: \"A\", content: \"198.51.100.4\", ttl: 3600})",
    )
  let assert Ok(domain) = dnsimple.find_domain(account, "lovelace.dev")
  assert list.any(domain.records, fn(r) {
    r.id == 104 && r.content == "198.51.100.4"
  })

  let assert Ok(#(_, account)) =
    run("context.delete_zone_record(\"lovelace.dev\", 106)")
  let assert Ok(domain) = dnsimple.find_domain(account, "lovelace.dev")
  assert !list.any(domain.records, fn(r) { r.id == 106 })
}

pub fn auto_renewal_is_changed_test() {
  let assert Ok(#(_, account)) =
    run("context.enable_domain_auto_renewal(\"notes.garden\")")
  let assert Ok(domain) = dnsimple.find_domain(account, "notes.garden")
  assert domain.auto_renew
  let assert Ok(#(_, account)) =
    run("context.disable_domain_auto_renewal(\"lovelace.dev\")")
  let assert Ok(domain) = dnsimple.find_domain(account, "lovelace.dev")
  assert !domain.auto_renew
}

pub fn a_missing_zone_fails_with_the_message_of_the_api_test() {
  let assert Error(reason) = run("context.list_zone_records(\"lovelace.com\")")
  assert string.contains(reason, "Zone `lovelace.com` not found")
}

pub fn requests_can_be_answered_over_http_test() {
  let #(status, body, _) =
    dnsimple.respond(dnsimple.fixture(), "GET", "/v2/whoami", <<>>)
  assert status == 200
  let assert Ok(text) = bit_array.to_string(body)
  assert string.contains(text, "ada@lovelace.dev")
}

fn agent(code, effects) {
  let environment = environment()
  let code = case code {
    "?" -> "todo"
    code -> environment.pin_packages(code, environment)
  }
  let assert Ok(tree) = parser.all_from_string(code)
  let config =
    options.Config(
      ..options.default_config(),
      focus_holes: True,
      effects:,
      search_libraries: True,
    )
  agent.new("", action.todo_holes(e.from_annotated(tree)), environment, config)
}

fn keys(agent) {
  agent.options(agent) |> list.map(options.key)
}

pub fn effects_can_be_hidden_test() {
  assert !list.contains(keys(agent("?", options.NoEffects)), "perform Print")
  assert list.contains(
    keys(agent("?", options.EffectSignatures)),
    "perform Print",
  )
}

pub fn the_effects_of_each_call_can_be_shown_test() {
  let program = "context.list_zone_records(\"lovelace.dev\")"
  let state = fn(effects) {
    json.to_string(agent.state(agent(program, effects)))
  }
  assert string.contains(
    state(options.EffectNodes),
    "context.list_zone_records(\\\"lovelace.dev\\\") performs DNSimple",
  )
  assert !string.contains(state(options.EffectSignatures), "effects_performed")
}

pub fn the_readme_examples_have_their_strings_as_holes_test() {
  let assert Some(readme) = environment.context_readme(environment())
  let assert [first, second, third, fourth, fifth, sixth] =
    options.readme_examples(readme)
  assert first == "@standard.list.length(context.list_zone_records(todo))"
  assert string.starts_with(second, "@standard.list.filter(")
  assert string.starts_with(third, "@standard.list.map(")
  assert string.starts_with(fourth, "@standard.list.flat_map(")
  assert string.contains(fifth, "context.create_zone_record(todo, {")
  assert string.contains(sixth, "context.delete_zone_record(todo, record.id)")
}

pub fn compounds_are_built_from_the_context_test() {
  let keys = fn(strategy) {
    let config =
      options.Config(
        ..options.default_config(),
        focus_holes: True,
        context_compounds: strategy,
      )
    agent.new("", e.Vacant, environment(), config)
    |> agent.options
    |> list.map(options.key)
  }
  assert list.contains(keys(options.ContextCalls), "context.list_domains({})")
  assert list.contains(
    keys(options.ContextBareCalls),
    "call context.list_domains(?)",
  )
  assert list.contains(
    keys(options.ContextExamples),
    "example @standard.list.length(context.list_zone_records(?))",
  )
  assert !list.contains(
    keys(options.NoContextCompounds),
    "context.list_domains({})",
  )
}

pub fn the_library_can_be_opened_test() {
  let agent = agent("?", options.EffectCallsOnly)
  assert list.contains(keys(agent), "open library @standard")
  let assert Ok(option) =
    list.find(agent.options(agent), fn(o) {
      options.key(o) == "open library @standard"
    })
  let assert Ok(agent) = agent.take(agent, agent.scripted(option.action))
  let offered = keys(agent)
  assert list.contains(offered, "library @standard")
  assert list.contains(offered, "call @standard.list.length(items)")
  assert list.contains(
    offered,
    "call @standard.list.filter(predicate, haystack)",
  )
}

pub fn arguments_of_context_functions_are_named_test() {
  let state =
    agent("context.update_zone_record(todo, todo, todo)", options.NoEffects)
    |> agent.state
    |> json.to_string
  assert string.contains(
    state,
    "argument 1 of 3, `zone`, to context.update_zone_record",
  )
}

pub fn context_functions_are_offered_where_a_function_is_expected_test() {
  let offered =
    keys(agent(
      "@standard.list.map(context.get_domain_delegation(\"notes.garden\"), todo)",
      options.NoEffects,
    ))
  assert list.contains(offered, "context.get_domain")
}

pub fn each_argument_of_a_complete_program_can_be_selected_test() {
  let program = "context.get_zone_record(\"lovelace.dev\", 104)"
  let jumps =
    agent.options(agent(program, options.EffectSignatures))
    |> list.filter(fn(option) {
      case option.action {
        action.JumpTo(..) -> True
        _ -> False
      }
    })
  let assert [zone, ..] = jumps
  assert zone.name == "select \"lovelace.dev\""
  assert string.contains(zone.description, "`zone`")
  assert list.length(jumps) == 2
}

pub fn a_complete_program_can_be_wrapped_twice_test() {
  let wrap = fn(agent, key) {
    let assert Ok(option) =
      list.find(agent.options(agent), fn(o) { options.key(o) == key })
    let assert Ok(agent) = agent.take(agent, agent.scripted(option.action))
    agent
  }
  let agent =
    agent("context.whoami({}).account.email", options.EffectSignatures)
    |> wrap("wrap in context.get_domain(..)")
    |> wrap("wrap in context.list_zone_records(..)")
  assert agent.program_text(agent)
    == "«context.list_zone_records(context.get_domain(context.whoami({}).account.email))»"
}

pub fn the_fields_of_a_complete_program_can_be_selected_test() {
  let offered = keys(agent("context.whoami({})", options.EffectSignatures))
  assert list.contains(offered, "select .account")
  assert !list.contains(offered, "string \"\"")
}

pub fn a_function_given_where_one_is_expected_is_finished_test() {
  let agent =
    agent(
      "@standard.list.map(context.get_domain_delegation(\"notes.garden\"), todo)",
      options.EffectSignatures,
    )
  let assert Ok(option) =
    list.find(agent.options(agent), fn(o) {
      options.key(o) == "context.get_domain"
    })
  let assert Ok(agent) = agent.take(agent, agent.scripted(option.action))
  assert string.contains(agent.program_text(agent), "context.get_domain\n)»")
}
