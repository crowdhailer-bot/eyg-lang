//// Run evals with each variant against the real API and write a table of the results.
//// Jev picks the same edits for the same request, so each pair runs once.
//// `TYPESAFE_API_KEY=... gleam run -m jev_playground/sweep --runtime bun -- [eval ...]`

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string
import jev_playground/client
import jev_playground/eval
import jev_playground/evaluate.{type Summary}
import plinth/javascript/date
import plinth/node/process
import simplifile

/// Holes first, then compounds by number and instances, then the whole program.
const variants = [
  ["holes"],
  ["compounds=5", "holes"],
  ["compounds", "holes"],
  ["compounds", "instances=2", "holes"],
  ["compounds", "instances=10", "holes"],
  [],
  ["compounds"],
]

pub fn main() {
  let evals = case argv.load().arguments {
    [] -> eval.all()
    slugs -> list.filter_map(slugs, eval.find)
  }
  let assert Ok(key) =
    list.key_find(array.to_list(process.env()), "TYPESAFE_API_KEY")
  let runs =
    list.flat_map(evals, fn(the_eval) {
      list.map(variants, fn(flags) { #(the_eval, eval.variant(flags)) })
    })
  use summaries <- promise.map(sequence(runs, [], client.Direct(key)))
  let report = table(summaries)
  let file =
    evaluate.directory
    <> "/sweep-"
    <> int.to_string(date.get_time(date.now()))
    <> ".md"
  let assert Ok(Nil) = simplifile.write(file, report)
  io.println(report)
  io.println(file)
}

fn sequence(runs, done, transport) -> Promise(List(Summary)) {
  case runs {
    [] -> promise.resolve(list.reverse(done))
    [#(the_eval, variant), ..rest] -> {
      use summary <- promise.await(evaluate.run(the_eval, variant, transport))
      io.println(evaluate.summary_line(summary))
      sequence(rest, [summary, ..done], transport)
    }
  }
}

/// One row per eval and a column per variant, each cell the steps and cost of
/// a solution or ✗, then totals per variant.
pub fn table(summaries: List(Summary)) -> String {
  let variant_names = list.map(summaries, fn(s) { s.variant }) |> list.unique
  let eval_names = list.map(summaries, fn(s) { s.eval }) |> list.unique
  let row = fn(cells) { "| " <> string.join(cells, " | ") <> " |" }
  let header = row(["eval", ..variant_names])
  let rule = row(list.repeat("---", list.length(variant_names) + 1))
  let rows =
    list.map(eval_names, fn(name) {
      row([
        name,
        ..list.map(variant_names, fn(variant) {
          case
            list.find(summaries, fn(s) {
              s.eval == name && s.variant == variant
            })
          {
            Ok(s) if s.solved ->
              int.to_string(s.steps) <> " steps " <> dollars(s.cost)
            Ok(s) -> "✗ " <> int.to_string(s.steps) <> " steps"
            Error(Nil) -> ""
          }
        })
      ])
    })
  let total = fn(label, cell) {
    row([
      label,
      ..list.map(variant_names, fn(variant) {
        cell(list.filter(summaries, fn(s) { s.variant == variant }))
      })
    ])
  }
  let totals = [
    total("solved", fn(runs: List(Summary)) {
      int.to_string(list.count(runs, fn(s) { s.solved }))
      <> " of "
      <> int.to_string(list.length(runs))
    }),
    total("steps to solve", fn(runs: List(Summary)) {
      list.filter(runs, fn(s) { s.solved })
      |> list.map(fn(s) { s.steps })
      |> int.sum
      |> int.to_string
    }),
    total("compound steps", fn(runs: List(Summary)) {
      int.to_string(int.sum(list.map(runs, fn(s) { s.compound_steps })))
    }),
    total("tokens", fn(runs: List(Summary)) {
      int.to_string(int.sum(list.map(runs, fn(s) { s.tokens })))
    }),
    total("cost", fn(runs: List(Summary)) {
      dollars(float.sum(list.map(runs, fn(s) { s.cost })))
    }),
    total("seconds", fn(runs: List(Summary)) {
      float.sum(list.map(runs, fn(s) { s.seconds }))
      |> float.round
      |> int.to_string
    }),
  ]
  string.join([header, rule, ..list.append(rows, totals)], "\n") <> "\n"
}

fn dollars(cost) {
  "$" <> float.to_string(float.to_precision(cost, 4))
}
