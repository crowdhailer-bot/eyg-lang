import jev_playground/vocabulary

pub fn records_are_labelled_by_the_labels_before_colons_test() {
  let vocabulary =
    vocabulary.from_task(
      "Return `{name: name, age: age}`, the library exports `{length, sum}`.",
    )
  assert vocabulary.records == [["name", "age"], ["length", "sum"]]
}

pub fn values_written_without_quotes_are_offered_as_strings_test() {
  let vocabulary =
    vocabulary.from_task(
      "Point www.notes.garden at 203.0.113.7 with an A record before 2027-06-01, see `list.fold`.",
    )
  assert vocabulary.strings
    == [
      "www.notes.garden",
      "203.0.113.7",
      "www",
      "notes.garden",
      "2027-06-01",
      "A",
    ]
}
