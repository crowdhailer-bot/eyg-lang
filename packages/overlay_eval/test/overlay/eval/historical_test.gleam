import eyg/interpreter/value
import gleam/json
import gleam/list
import gleam/string
import overlay/eval/cassette
import overlay/eval/pure
import overlay/eval/report
import simplifile

pub fn historical_comparison_logs_and_cassettes_remain_readable_test() {
  list.each(
    [
      #("baseline", 7),
      #("compact-reference", 5),
      #("explicit-execution", 11),
    ],
    fn(expected) {
      let root = "evidence/2026-10-04/" <> expected.0
      let assert Ok(text) = simplifile.read(root <> "/run.json")
      let assert Ok(#(header, summary)) = json.parse(text, report.log_decoder())
      assert header.suite == "programs"
      assert header.trials_per_task == 3
      assert list.length(summary.tasks) == 4
      assert list.fold(summary.tasks, 0, fn(n, task) { n + task.trials }) == 12
      assert list.fold(summary.tasks, 0, fn(n, task) { n + task.passes })
        == expected.1
      let assert Ok(files) =
        simplifile.read_directory(root <> "/cassettes/none")
      assert list.length(files) == 12
      list.each(files, fn(file) {
        let assert Ok(text) =
          simplifile.read(root <> "/cassettes/none/" <> file)
        let assert Ok(cassette) = json.parse(text, cassette.decoder())
        assert cassette.interactions != []
        list.each(cassette.interactions, fn(interaction) {
          assert string.length(interaction.key) == 64
          assert interaction.status == 200
          assert interaction.body != <<>>
        })
      })
    },
  )
}

pub fn historical_pure_programs_keep_their_reported_values_test() {
  let assert Ok(text) = simplifile.read("evidence/fibonacci.md")
  let programs =
    string.split(text, "```eyg\n")
    |> list.drop(1)
    |> list.map(fn(section) {
      let assert Ok(#(code, _)) = string.split_once(section, "\n```")
      code
    })
  let assert [wrong, correct] = programs
  assert pure.evaluate(wrong) == Ok(value.Integer(28_655))
  assert pure.evaluate(correct) == Ok(value.Integer(17_710))
}
