import argv
import bench/command
import bench/report
import bench/trial
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import simplifile

pub fn main() {
  case argv.load().arguments {
    ["trial", variant, workload, rows, number] -> {
      let assert Ok(rows) = int.parse(rows)
      let assert Ok(number) = int.parse(number)
      use report <- promise.map(trial.run(variant, workload, rows, number))
      io.println(json.to_string(report))
    }
    ["matrix"] -> matrix()
    ["report"] -> {
      report.main()
      promise.resolve(Nil)
    }
    _ ->
      panic as "usage: gleam run -- trial core|lustre|signals stream|typing ROWS TRIAL | matrix"
  }
}

fn matrix() {
  let assert Ok(_) = simplifile.create_directory_all("results")
  let cases =
    list.flat_map(["stream", "typing"], fn(workload) {
      list.flat_map([20, 200], fn(rows) {
        list.flat_map([1, 2, 3, 4, 5], fn(number) {
          let variants = ["core", "lustre", "signals"]
          let shift = { number - 1 } % 3
          let variants =
            list.append(list.drop(variants, shift), list.take(variants, shift))
          list.map(variants, fn(variant) { #(variant, workload, rows, number) })
        })
      })
    })
  use revision <- promise.await(command.run(["git", "rev-parse", "HEAD"]))
  assert revision.0 == 0
  let assert Ok(_) =
    simplifile.write(
      "results/frontend-revision.txt",
      string.trim(revision.1) <> "\n",
    )
  run_cases(cases)
}

fn run_cases(cases) {
  case cases {
    [] -> {
      io.println("PASS 60 fresh native frontend trials")
      promise.resolve(Nil)
    }
    [#(variant, workload, rows, number), ..rest] -> {
      let name =
        variant
        <> "-"
        <> workload
        <> "-"
        <> int.to_string(rows)
        <> "-"
        <> int.to_string(number)
      use output <- promise.await(
        command.run([
          "gleam",
          "run",
          "--no-print-progress",
          "--",
          "trial",
          variant,
          workload,
          int.to_string(rows),
          int.to_string(number),
        ]),
      )
      let assert Ok(_) =
        simplifile.write("results/" <> name <> ".log", output.2)
      assert output.0 == 0 as { output.2 <> output.1 }
      let assert Ok(_) = json.parse(string.trim(output.1), decode.dynamic)
      let assert Ok(_) =
        simplifile.write(
          "results/" <> name <> ".json",
          string.trim(output.1) <> "\n",
        )
      io.println("PASS " <> name)
      run_cases(rest)
    }
  }
}
