import gleam/int
import gleam/list
import gleam/option.{Some}
import jev_playground/action
import jev_playground/agent
import jev_playground/demo
import jev_playground/mock
import morph/editable as e

fn replay(demo: demo.Demo) {
  let assert Ok(actions) = demo.script(demo)
  let agent = agent.new(demo.task, e.Vacant, demo.environment, demo.config)
  list.index_fold(actions, agent, fn(agent, action, i) {
    let offered = agent.options(agent)
    let #(evaluation, thinking_ms) = case mock.answer(offered, action, i) {
      Ok(answer) -> answer
      Error(reason) ->
        panic as {
          "step "
          <> int.to_string(i + 1)
          <> ": "
          <> reason
          <> "\n"
          <> agent.program_text(agent)
        }
    }
    case agent.answer(agent, offered, evaluation, thinking_ms) {
      Ok(agent) -> agent
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
  let assert Ok(actions) = demo.script(demo.github())
  assert list.last(actions) == Ok(action.Finish)
}
