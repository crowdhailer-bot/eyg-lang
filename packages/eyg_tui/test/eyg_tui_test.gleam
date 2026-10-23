import eyg/cli/internal/config
import eyg/cli/tui/host
import eyg/cli/tui/shell
import gleam/option.{None}
import gleam/string
import gleeunit

pub fn main() {
  gleeunit.main()
}

fn started() {
  let assert Ok(Ok(config)) = host.run(config.load())
  let assert Ok(Ok(started)) = host.run(shell.start(None, config))
  started
}

pub fn output_and_effects_are_reported_test() {
  let effect = shell.evaluate(started(), "perform StandardOut(\"hello\")")
  let assert Ok(#(events, shell.Finished(evaluated))) =
    host.advance(effect, 0.0)
  assert events == [shell.Output("hello", False)]
  assert evaluated.results == [Ok("{}")]
  assert evaluated.performed
    == [shell.Performed("StandardOut", "\"hello\"", "{}", None)]
}

pub fn standard_input_asks_and_resumes_test() {
  let source =
    "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }"
  let assert Ok(#(_, shell.Asking("Standard input", resume))) =
    host.advance(shell.evaluate(started(), source), 0.0)
  let assert Ok(#(_, shell.Finished(evaluated))) =
    host.advance(resume("typed"), 0.0)
  assert evaluated.results == [Ok("Ok(\"typed\")")]
}

pub fn network_requests_fail_without_stopping_the_shell_test() {
  let effect = shell.evaluate(started(), "@standard.integer.add(1, 2)")
  let assert Ok(#(events, shell.Finished(evaluated))) =
    host.advance(effect, 0.0)
  let assert [shell.Fetched(_), ..] = events
  let assert [Error(reason)] = evaluated.results
  assert string.contains(reason, "standard")
}

pub fn operations_without_an_implementation_stop_the_evaluation_test() {
  let effect = shell.evaluate(started(), "perform Sleep(10)")
  let assert Error(reason) = host.advance(effect, 0.0)
  assert reason == "Wait needs the JavaScript runtime"
}
