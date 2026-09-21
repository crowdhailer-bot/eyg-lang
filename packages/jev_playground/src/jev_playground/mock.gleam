//// Stand in for Jev by replaying a script of actions.
//// Answers look like real ones: the scripted option is most likely and a few
//// other offered options share the rest, so recordings exercise the same code
//// as live runs without calling the API.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import jev
import jev_playground/action.{type Action}
import jev_playground/agent
import jev_playground/options

/// The answer Jev would give when choosing `action`, with a thinking time in milliseconds.
pub fn answer(
  offered: List(options.Option),
  action: Action,
  step: Int,
) -> Result(#(jev.Evaluation, Int), String) {
  use chosen <- result.try(
    list.find(offered, fn(option) { option.action == action })
    |> result.replace_error(
      "the script chose " <> action.key(action) <> " which is not offered",
    ),
  )
  let seed = step * 7919 + 17
  let confidence = 0.55 +. to_unit(seed) *. 0.44
  // Close alternatives are options of the same kind, such as another variable.
  let kind = fn(option) {
    options.key(option) |> string.split(" ") |> list.first
  }
  let #(similar, different) =
    list.filter(offered, fn(option) { option.action != action })
    |> list.partition(fn(option) { kind(option) == kind(chosen) })
  let others =
    list.append(pick(similar, seed, 2), pick(different, seed + 1, 3))
    |> list.take(4)
  let remainder = 1.0 -. confidence
  let weights = [0.55, 0.25, 0.14, 0.06]
  let probabilities =
    list.zip(others, weights)
    |> list.map(fn(pair) {
      let #(option, weight) = pair
      #(options.key(option), round(remainder *. weight))
    })
    |> list.prepend(#(options.key(chosen), round(confidence)))
  let answer =
    jev.ChoiceAnswer(
      choice: options.key(chosen),
      probabilities: dict.from_list(probabilities),
      confidence: round(confidence *. 0.95),
    )
  let evaluation =
    jev.Evaluation(
      model: "jev-1.13.0",
      answers: dict.from_list([#(agent.question_id, answer)]),
      usage: jev.Usage(
        input_tokens: 400 + list.length(offered) * 30,
        output_tokens: 20,
      ),
    )
  let thinking_ms = 180 + float.round(to_unit(seed * 31 + 5) *. 520.0)
  Ok(#(evaluation, thinking_ms))
}

fn round(x) {
  int.to_float(float.round(x *. 100.0)) /. 100.0
}

// A deterministic pseudo random number in [0, 1).
fn to_unit(seed) {
  let x = { seed * 1_103_515 + 12_345 } % 1_000_003
  int.to_float(int.absolute_value(x)) /. 1_000_003.0
}

fn pick(items, seed, count) {
  let size = list.length(items)
  case size {
    0 -> []
    _ ->
      int.range(from: 0, to: count, with: [], run: fn(acc, i) { [i, ..acc] })
      |> list.reverse
      |> list.map(fn(i) { { seed * { i + 3 } * 131 } % size })
      |> list.unique
      |> list.filter_map(fn(index) { list.drop(items, index) |> list.first })
  }
}
