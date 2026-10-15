//// Validate retained samples and summarize independent native-renderer trials.

import bench/trial
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import simplifile

pub type Trial {
  Trial(
    variant: String,
    workload: String,
    rows: Int,
    number: Int,
    bun: String,
    mean: Float,
    p95: Float,
    mount: Float,
    history: Float,
    latencies: List(Float),
    recorded: Float,
  )
}

fn decoder() {
  use variant <- decode.field("variant", decode.string)
  use workload <- decode.field("workload", decode.string)
  use rows <- decode.field("history_rows", decode.int)
  use number <- decode.field("trial", decode.int)
  use bun <- decode.field("bun", decode.string)
  use mean <- decode.field("mean_ms", decode.float)
  use p95 <- decode.field("p95_ms", decode.float)
  use mount <- decode.field("mount_ms", decode.float)
  use history <- decode.field("history_ms", decode.float)
  use latencies <- decode.field("latencies_ms", decode.list(decode.float))
  use recorded <- decode.optional_field("recorded_unix_ms", 0.0, decode.float)
  decode.success(Trial(
    variant,
    workload,
    rows,
    number,
    bun,
    mean,
    p95,
    mount,
    history,
    latencies,
    recorded,
  ))
}

pub fn read(directory, variants) {
  let assert Ok(files) = simplifile.read_directory(directory)
  let files =
    list.filter(files, fn(file) {
      string.ends_with(file, ".json") && file != "summary.json"
    })
  let trials =
    list.map(files, fn(file) {
      let assert Ok(code) = simplifile.read(directory <> "/" <> file)
      let assert Ok(value) = json.parse(code, decoder())
      assert list.length(value.latencies) == 120
      assert list.all(value.latencies, fn(ms) { ms >=. 0.0 })
      assert float.absolute_value(value.mean -. trial.mean(value.latencies))
        <. 0.000001
      assert float.absolute_value(
          value.p95 -. trial.percentile(value.latencies, 0.95),
        )
        <. 0.000001
      value
    })
  assert list.length(trials) == list.length(variants) * 20
  let identities =
    list.map(trials, fn(t) { #(t.variant, t.workload, t.rows, t.number) })
  assert list.length(list.unique(identities)) == list.length(trials)
  list.each(variants, fn(variant) {
    list.each(["stream", "typing"], fn(workload) {
      list.each([20, 200], fn(rows) {
        let selected =
          list.filter(trials, fn(t) {
            t.variant == variant && t.workload == workload && t.rows == rows
          })
        assert list.map(selected, fn(t) { t.number }) |> list.sort(int.compare)
          == [1, 2, 3, 4, 5]
      })
    })
  })
  trials
}

fn median(values) {
  list.sort(values, float.compare)
  |> list.drop(list.length(values) / 2)
  |> list.first
  |> result.unwrap(0.0)
}

fn short(value) {
  float.to_string(int.to_float(float.round(value *. 100.0)) /. 100.0)
}

pub fn main() {
  let variants = ["core", "lustre", "signals"]
  let trials = read("results", variants)
  let historical = read("historical", ["typescript", ..variants])
  let assert Ok(revision) = simplifile.read("results/frontend-revision.txt")
  let rows =
    list.flat_map(["stream", "typing"], fn(workload) {
      list.flat_map([20, 200], fn(history) {
        list.map(variants, fn(variant) {
          let selected =
            list.filter(trials, fn(t) {
              t.variant == variant
              && t.workload == workload
              && t.rows == history
            })
          let means = list.map(selected, fn(t) { t.mean })
          #(
            variant,
            workload,
            history,
            median(means),
            median(list.map(selected, fn(t) { t.p95 })),
            list.fold(means, 1_000_000.0, float.min),
            list.fold(means, 0.0, float.max),
            median(list.map(selected, fn(t) { t.mount })),
            median(list.map(selected, fn(t) { t.history })),
          )
        })
      })
    })
  let recorded =
    list.fold(trials, 0.0, fn(latest, trial) {
      float.max(latest, trial.recorded)
    })
    /. 1000.0
    |> float.truncate
    |> timestamp.from_unix_seconds
    |> timestamp.to_rfc3339(duration.seconds(0))
  let markdown =
    "# Native terminal comparison\n\nLast trial recorded at "
    <> recorded
    <> ". Frontend revision: "
    <> string.trim(revision)
    <> ".\n\nMedians of five trial means and five trial p95s. Ranges show observed trial means, not confidence intervals.\n\n| Workload | Rows | Frontend | Mean ms | p95 ms | Mean range ms | Mount ms | History ms |\n|---|---:|---|---:|---:|---|---:|---:|\n"
    <> string.concat(
      list.map(rows, fn(row) {
        "| "
        <> row.1
        <> " | "
        <> int.to_string(row.2)
        <> " | "
        <> row.0
        <> " | "
        <> short(row.3)
        <> " | "
        <> short(row.4)
        <> " | "
        <> short(row.5)
        <> "–"
        <> short(row.6)
        <> " | "
        <> short(row.7)
        <> " | "
        <> short(row.8)
        <> " |\n"
      }),
    )
  let assert Ok(_) = simplifile.write("results/summary.md", markdown)
  let json =
    json.object([
      #("frontend_revision", json.string(string.trim(revision))),
      #("recorded", json.string(recorded)),
      #(
        "aggregation",
        json.string(
          "Median of five trial means and five trial p95s; ranges are observed trial variation",
        ),
      ),
      #(
        "rows",
        json.array(rows, fn(row) {
          json.object([
            #("variant", json.string(row.0)),
            #("workload", json.string(row.1)),
            #("history_rows", json.int(row.2)),
            #("mean_ms", json.float(row.3)),
            #("p95_ms", json.float(row.4)),
            #("min_trial_mean_ms", json.float(row.5)),
            #("max_trial_mean_ms", json.float(row.6)),
          ])
        }),
      ),
    ])
  let assert Ok(_) =
    simplifile.write("results/summary.json", json.to_string(json) <> "\n")
  io.println(markdown)
  io.println(
    "PASS "
    <> int.to_string(list.length(trials))
    <> " fresh trials and "
    <> int.to_string(list.length(historical))
    <> " historical trials: complete matrices and recomputed statistics",
  )
}
