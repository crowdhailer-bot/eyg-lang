import eyg/parser
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jev_playground/agent
import jev_playground/dnsimple
import jev_playground/environment
import jev_playground/eval as evals
import jev_playground/library
import jev_playground/options
import jev_playground/packages
import morph/editable as e
import simplifile

fn environment() {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, environment.pure())
  environment
}

// Evals with a context use the DNSimple context from `eyg_packages`, which a
// test elsewhere checks is the module shared to the hub.
fn environment_for(eval: evals.Eval, base) {
  case eval.context {
    Some(_) -> {
      let assert Ok(text) = simplifile.read(dnsimple.context_path)
      let assert Ok(source) = library.parse(text)
      let assert Ok(bundle) = packages.bundle()
      let assert Ok(base) = library.environment(bundle, environment.browser())
      let assert Ok(environment) = library.context(source, base)
      environment
    }
    None -> base
  }
}

fn annotated(source) {
  let assert Ok(tree) = parser.all_from_string(source)
  e.to_annotated(e.from_annotated(tree), [])
}

// Solutions are written with the short package name, as the readme is.
fn annotated_in(source, environment) {
  annotated(environment.pin_packages(source, environment))
}

pub fn every_solution_passes_its_check_test() {
  let environment = environment()
  list.each(evals.all(), fn(eval) {
    let environment = environment_for(eval, environment)
    let source = annotated_in(evals.solution(eval), environment)
    assert evals.check(eval, source, environment) == Ok(Nil)
  })
}

pub fn the_mail_servers_answer_the_mx_question_test() {
  let assert Ok(eval) = evals.find("dnsimple-mx")
  let environment = environment_for(eval, environment.pure())
  let check = fn(code) {
    evals.check(eval, annotated_in(code, environment), environment)
  }
  let values = fn(type_) {
    "@standard.list.map(@standard.list.filter((record) -> { !equal(record.type, \""
    <> type_
    <> "\") }, context.list_zone_records(\"analytical.engineering\")), (record) -> { record.content })"
  }
  assert check(values("MX")) == Ok(Nil)
  let assert Error(_) = check(values("A"))
}

pub fn list_functions_start_fails_its_check_test() {
  let eval = evals.list_functions()
  let assert Error(reason) =
    evals.check(eval, annotated(eval.start), environment())
  assert reason == "the record has no `sum`"
}

pub fn every_start_fails_its_check_test() {
  let environment = environment()
  list.each(evals.all(), fn(eval) {
    let assert Ok(start) = evals.start(eval)
    let assert Error(_) =
      evals.check(
        eval,
        e.to_annotated(start, []),
        environment_for(eval, environment),
      )
  })
}

pub fn variants_are_named_by_their_flags_test() {
  assert evals.variant_name(evals.variant([])) == "improved"
  assert evals.variant_name(evals.variant(["compounds", "holes"]))
    == "compounds-holes"
  assert evals.variant_name(
      evals.variant(["compounds=5", "instances=2", "holes"]),
    )
    == "compounds5-instances2-holes"
  assert evals.variant_name(
      evals.variant(["holes", "types", "cursors=3", "nojumps", "mark=comments"]),
    )
    == "holes-types-cursors3-nojumps-markcomments"
  assert evals.variant_name(evals.variant(["holes", "mark=excerpt"])) == "holes"
  assert evals.variant_name(evals.variant(["holes", "mark=guillemets"]))
    == "holes-markguillemets"
}

pub fn a_recursive_call_in_a_scaffold_takes_every_argument_test() {
  let eval = evals.fibonacci_scaffold()
  let assert Ok(start) = evals.start(eval)
  let config = evals.config(eval, evals.variant(["holes"]))
  let agent = agent.new(eval.task, start, environment(), config)
  let assert Ok(option) =
    list.find(agent.options(agent), fn(option) {
      options.key(option) == "call go(?, ?, ?, ?)"
    })
  let assert Ok(agent) = agent.take(agent, agent.scripted(option.action))
  assert string.contains(
    agent.program_text(agent),
    "Gt(_) -> { go(«?», ?, ?, ?) }",
  )
}
