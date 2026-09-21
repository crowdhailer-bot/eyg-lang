//// Run evals with each variant against the real API and write a table of the results.
//// Jev mostly picks the same edits for the same request, but close calls can flip,
//// `repeat=3` runs each eval and variant three times.
//// `TYPESAFE_API_KEY=... gleam run -m jev_playground/sweep --runtime bun -- compounds|checked|ablations|cursors|experiments [repeat=3] [eval ...]`

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import gleam/string
import jev_playground/client
import jev_playground/eval
import jev_playground/evaluate.{type Summary}
import plinth/javascript/date
import plinth/node/process
import simplifile

/// Holes first, then compounds by number and instances, then the whole program.
const compound_variants = [
  ["holes"],
  ["compounds=5", "holes"],
  ["compounds", "holes"],
  ["compounds", "instances=2", "holes"],
  ["compounds", "instances=10", "holes"],
  [],
  ["compounds"],
]

/// Several holes per request against one.
const cursor_variants = [
  ["holes"],
  ["holes", "cursors=2"],
  ["holes", "cursors=3"],
]

/// Each earlier improvement turned off in turn.
const ablation_variants = [
  ["holes"],
  ["holes", "flat"],
  ["holes", "untyped"],
  ["holes", "repeats"],
]

/// Compounds with each instance applied before it is offered.
const checked_variants = [
  ["compounds", "holes"],
  ["compounds", "holes", "checked"],
  ["compounds"],
  ["compounds", "checked"],
]

/// The other ways of offering choices, each against its baseline.
const experiment_variants = [
  ["holes"],
  ["holes", "types"],
  ["holes", "cursors=3"],
  ["holes", "types", "cursors=3"],
  ["holes", "nojumps"],
  ["holes", "mark=comments"],
  ["holes", "mark=unmarked"],
  ["holes", "mark=excerpt"],
  [],
  ["types"],
  ["nojumps"],
  ["mark=comments"],
  ["mark=unmarked"],
  ["mark=excerpt"],
]

pub fn main() {
  let assert [set, ..rest] = argv.load().arguments
  // `repeat=3` runs each eval and variant three times, as close calls can flip.
  let #(repeats, slugs) = list.partition(rest, string.starts_with(_, "repeat="))
  let repeats = case repeats {
    ["repeat=" <> n, ..] -> int.parse(n) |> result.unwrap(1)
    _ -> 1
  }
  let variants = case set {
    "compounds" -> compound_variants
    "checked" -> checked_variants
    "ablations" -> ablation_variants
    "cursors" -> cursor_variants
    _ -> experiment_variants
  }
  let evals = case slugs {
    [] -> eval.all()
    slugs -> list.filter_map(slugs, eval.find)
  }
  let assert Ok(key) =
    list.key_find(array.to_list(process.env()), "TYPESAFE_API_KEY")
  let runs =
    list.flat_map(evals, fn(the_eval) {
      list.flat_map(variants, fn(flags) {
        list.repeat(#(the_eval, eval.variant(flags)), repeats)
      })
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
          let runs =
            list.filter(summaries, fn(s) {
              s.eval == name && s.variant == variant
            })
          case runs {
            [] -> ""
            [s] if s.solved -> requests(s) <> " " <> dollars(s.cost)
            [s] -> "✗ " <> requests(s)
            _ -> repeated(runs)
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
    total("requests", fn(runs: List(Summary)) {
      int.to_string(int.sum(list.map(runs, fn(s) { s.requests })))
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

// Steps, and the requests they took when several holes were filled at once.
fn requests(summary: Summary) {
  case summary.requests == summary.steps {
    True -> int.to_string(summary.steps) <> " steps"
    False ->
      int.to_string(summary.steps)
      <> " steps in "
      <> int.to_string(summary.requests)
      <> " requests"
  }
}

// How many of the repeated runs solved the eval and the median steps they took.
fn repeated(runs: List(Summary)) {
  let solved =
    list.filter(runs, fn(s) { s.solved })
    |> list.map(fn(s) { s.steps })
    |> list.sort(int.compare)
  let count =
    int.to_string(list.length(solved))
    <> "/"
    <> int.to_string(list.length(runs))
  case list.drop(solved, list.length(solved) / 2) {
    [median, ..] -> count <> ", " <> int.to_string(median) <> " steps"
    [] -> count
  }
}
