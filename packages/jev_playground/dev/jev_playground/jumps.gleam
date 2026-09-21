//// Replay every saved eval run and report how Jev used navigation,
//// in particular what the edit after a jump to a type error did.
//// Runs are replayed with the current code, so only runs saved since a time are read.
//// `gleam run -m jev_playground/jumps --runtime bun -- 1790000000000`

import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/environment
import jev_playground/eval
import jev_playground/evaluate
import jev_playground/library
import jev_playground/packages
import morph/editable as e
import simplifile

pub fn main() {
  let assert Ok(bundle) = packages.bundle()
  let assert Ok(environment) = library.environment(bundle, environment.pure())
  let assert [since] = argv.load().arguments
  let assert Ok(since) = int.parse(since)
  let assert Ok(files) = simplifile.read_directory(evaluate.directory)
  let runs =
    files
    |> list.filter(fn(file) { saved(file) >= since })
    |> list.filter_map(fn(file) {
      use text <- result.try(
        simplifile.read(evaluate.directory <> "/" <> file)
        |> result.replace_error(Nil),
      )
      json.parse(text, eval.run_decoder()) |> result.replace_error(Nil)
    })
  let replays = list.map(runs, replay(_, environment))
  let steps = list.flatten(replays)
  let count = fn(predicate) { list.count(steps, predicate) }
  let navigation =
    count(fn(s: Replayed) { action.is_navigation(s.step.action) })
  io.println(
    int.to_string(list.length(runs))
    <> " runs, "
    <> int.to_string(list.length(steps))
    <> " steps, "
    <> int.to_string(navigation)
    <> " navigation",
  )
  let kinds =
    list.filter(steps, fn(s: Replayed) { action.is_navigation(s.step.action) })
    |> list.map(fn(s: Replayed) { kind(s.step.action) })
  io.println("navigation by kind: " <> tally(kinds))
  // Each jump with the step after it.
  let jumps =
    list.flat_map(replays, fn(steps) {
      list.window_by_2(steps)
      |> list.filter(fn(pair) {
        case { pair.0 }.step.action {
          action.JumpToError(_) -> True
          _ -> False
        }
      })
    })
  let outcomes =
    list.map(jumps, fn(pair) {
      let #(jump, next) = pair
      case int.compare(next.errors, jump.errors) {
        _ if next.step.failed -> "the next edit failed"
        order.Lt -> "the next edit removed an error"
        order.Eq -> "the next edit left the errors"
        order.Gt -> "the next edit added an error"
      }
    })
  io.println(int.to_string(list.length(jumps)) <> " jumps to a type error")
  io.println("after a jump: " <> tally(outcomes))
  io.println(
    "edits after a jump: "
    <> tally(list.map(jumps, fn(pair) { kind({ pair.1 }.step.action) })),
  )
  let solved_with_jumps =
    list.count(list.zip(runs, replays), fn(pair) {
      let #(run, steps) = pair
      run.outcome == "solved"
      && list.any(steps, fn(s: Replayed) {
        case s.step.action {
          action.JumpToError(_) -> True
          _ -> False
        }
      })
    })
  io.println(
    int.to_string(solved_with_jumps)
    <> " of "
    <> int.to_string(list.count(runs, fn(run) { run.outcome == "solved" }))
    <> " solved runs jumped to an error",
  )
}

type Replayed {
  Replayed(step: agent.Step, errors: Int)
}

// Apply each saved step as the replay page does, noting the type errors after it.
fn replay(run: eval.Run, environment) -> List(Replayed) {
  let start = eval.start(run.eval) |> result.unwrap(e.Vacant)
  let config = eval.config(run.eval, run.variant)
  let agent = agent.new(run.eval.task, start, environment, config)
  let #(_, replayed) =
    list.fold(run.steps, #(agent, []), fn(acc, step) {
      let #(agent, replayed) = acc
      let before = agent.type_error_count(agent)
      let agent = case agent.take(agent, step) {
        Ok(agent) -> agent
        Error(_) -> agent
      }
      let errors = case step.action {
        action.JumpToError(_) -> before
        _ -> agent.type_error_count(agent)
      }
      #(agent, [Replayed(step:, errors:), ..replayed])
    })
  list.reverse(replayed)
}

// Files end with the time they were saved, `<eval>-<variant>-<time>.json`.
fn saved(file) {
  case string.ends_with(file, ".json") {
    False -> 0
    True ->
      string.drop_end(file, 5)
      |> string.split("-")
      |> list.last
      |> result.try(int.parse)
      |> result.unwrap(0)
  }
}

fn kind(action) {
  action.key(action)
  |> string.split(" ")
  |> list.take(2)
  |> string.join(" ")
}

fn tally(items: List(String)) {
  list.fold(items, dict.new(), fn(counts, item) {
    dict.upsert(counts, item, fn(count) {
      case count {
        option.Some(count) -> count + 1
        option.None -> 1
      }
    })
  })
  |> dict.to_list
  |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
  |> list.map(fn(entry) { entry.0 <> " " <> int.to_string(entry.1) })
  |> string.join(", ")
}
