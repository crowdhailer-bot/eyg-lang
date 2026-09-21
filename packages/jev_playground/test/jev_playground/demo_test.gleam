import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/demo
import jev_playground/library
import jev_playground/mock
import jev_playground/options
import jev_playground/packages
import morph/editable as e

fn environment(demo: demo.Demo) {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, demo.environment)
  environment
}

fn replay(demo: demo.Demo) {
  let environment = environment(demo)
  let demo.Prepared(task:, actions:) = case demo.prepare(demo, environment) {
    Ok(prepared) -> prepared
    Error(reason) -> panic as { demo.slug <> ": " <> reason }
  }
  let agent = agent.new(task, e.Vacant, environment, demo.config)
  list.index_fold(actions, agent, fn(agent, action, i) {
    let offered = agent.options(agent)
    let candidates = agent.candidates(agent, _)
    let #(evaluation, thinking_ms) = case
      mock.answer(offered, candidates, action, i)
    {
      Ok(answer) -> answer
      Error(reason) ->
        panic as {
          demo.slug
          <> " step "
          <> int.to_string(i + 1)
          <> ": "
          <> reason
          <> "\noffered "
          <> int.to_string(list.length(offered))
          <> ": "
          <> string.join(list.map(offered, options.key), " | ")
        }
    }
    case agent.answer(agent, offered, evaluation, thinking_ms) {
      Ok(agent) -> {
        let assert [step, ..] = agent.history
        case step.failed {
          True -> panic as { demo.slug <> " failed to " <> action.key(action) }
          False -> agent
        }
      }
      Error(reason) -> panic as reason
    }
  })
}

pub fn every_demo_replays_with_each_choice_offered_test() {
  list.each(demo.all(), fn(demo) {
    let agent = replay(demo)
    assert agent.finished
  })
}

pub fn github_demo_tests_pass_test() {
  let agent = replay(demo.github())
  assert agent.test_results == Some("3 of 3 tests passed")
}

pub fn compounds_shorten_the_http_demo_test() {
  let http = demo.http()
  let assert Ok(single) = demo.script(http, environment(http))
  let compound = demo.http_compound()
  let assert Ok(compressed) = demo.script(compound, environment(compound))
  assert list.length(compressed) < list.length(single)
}

pub fn github_library_demo_opens_http_and_tests_pass_test() {
  let agent = replay(demo.github_library())
  assert agent.config.open_libraries == ["http"]
  assert agent.test_results == Some("3 of 3 tests passed")
}
