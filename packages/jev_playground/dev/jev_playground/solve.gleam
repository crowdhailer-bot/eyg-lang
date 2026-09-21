//// Let Jev work on a task from an empty program, printing every choice.
//// `TYPESAFE_API_KEY=... gleam run -m jev_playground/solve -- "task" steps`

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/string
import jev
import jev_playground/action
import jev_playground/agent
import jev_playground/client
import jev_playground/environment
import jev_playground/options
import morph/editable as e
import plinth/node/process

pub fn main() {
  let assert [task, steps] = argv.load().arguments
  let assert Ok(steps) = int.parse(steps)
  let assert Ok(key) =
    list.key_find(array.to_list(process.env()), "TYPESAFE_API_KEY")
  let agent =
    agent.new(task, e.Vacant, environment.pure(), options.default_config())
  loop(agent, client.Direct(key), steps)
}

fn loop(agent: agent.Agent, transport, remaining) {
  case remaining, agent.finished {
    0, _ | _, True -> {
      io.println(agent.program_text(agent))
      promise.resolve(Nil)
    }
    _, False -> {
      let #(request, offered) = agent.request(agent, jev.latest)
      use reply <- promise.await(client.system_one(transport, request))
      case reply {
        Ok(client.Reply(evaluation:, thinking_ms:)) ->
          case agent.answer(agent, offered, evaluation, thinking_ms) {
            Ok(agent) -> {
              let assert [step, ..] = agent.history
              io.println(
                string.pad_start(
                  int.to_string(list.length(agent.history)),
                  3,
                  " ",
                )
                <> " "
                <> action.key(step.action)
                <> "  conf "
                <> float.to_string(step.confidence)
                <> " "
                <> int.to_string(thinking_ms)
                <> "ms "
                <> int.to_string(step.offered)
                <> " options "
                <> int.to_string(step.input_tokens)
                <> " tokens | next: "
                <> string.inspect(list.take(list.drop(step.ranked, 1), 3)),
              )
              io.println(
                "    "
                <> string.replace(agent.program_text(agent), "\n", "\n    "),
              )
              loop(agent, transport, remaining - 1)
            }
            Error(reason) -> {
              io.println("failed: " <> reason)
              promise.resolve(Nil)
            }
          }
        Error(reason) -> {
          io.println("request failed: " <> reason)
          promise.resolve(Nil)
        }
      }
    }
  }
}
