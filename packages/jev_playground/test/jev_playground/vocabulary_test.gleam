import jev_playground/vocabulary

pub fn records_are_labelled_by_the_labels_before_colons_test() {
  let vocabulary =
    vocabulary.from_task(
      "Return `{name: name, age: age}`, the library exports `{length, sum}`.",
    )
  assert vocabulary.records == [["name", "age"], ["length", "sum"]]
}
