import eyg/embed/shell.{Returned}
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{Some}
import todomvc/fixture
import todomvc/run.{Run}
import todomvc/tasks.{Task}

fn value(code) {
  let assert Run(outcome: Returned(Some(value)), ..) =
    run.run(fixture.shell(), fixture.tasks(), code)
  value
}

pub fn a_query_can_use_the_standard_library_test() {
  assert value("@standard.list.length(todos.all({}))") == v.Integer(4)
}

pub fn tasks_can_be_found_by_tag_test() {
  assert value(
      "let {list} = @standard\nlist.map(todos.tagged(\"#shopping\"), (task) -> { task.id })",
    )
    == v.LinkedList([v.Integer(1), v.Integer(3)])
}

pub fn tasks_can_be_matched_ignoring_case_test() {
  assert value(
      "let {list} = @standard\nlist.map(todos.matching(\"BUY\"), (task) -> { task.title })",
    )
    == v.LinkedList([
      v.String("Buy milk #shopping"),
      v.String("Buy bread #shopping"),
    ])
}

pub fn a_program_can_change_many_tasks_at_once_test() {
  let assert Run(tasks:, outcome: Returned(_), ..) =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let {list} = @standard\nlist.map(todos.tagged(\"#shopping\"), todos.complete)",
    )
  assert tasks.all(tasks)
    == [
      Task(1, "Buy milk #shopping", True),
      Task(2, "Call the plumber", False),
      Task(3, "Buy bread #shopping", True),
      Task(4, "Write the EYG post #work", False),
    ]
}

pub fn a_program_can_create_tasks_test() {
  let assert Run(tasks:, outcome: Returned(Some(id)), ..) =
    run.run(fixture.shell(), fixture.tasks(), "todos.add(\"Book dentist\")")
  assert id == v.Integer(5)
  let assert [_, _, _, _, Task(5, "Book dentist", False)] = tasks.all(tasks)
}

pub fn deleting_is_not_an_effect_test() {
  let assert Run(outcome: shell.TypeFailed(reasons), ..) =
    run.run(fixture.shell(), fixture.tasks(), "perform DeleteTask(1)")
  assert reasons == ["line 1: missing row 'DeleteTask'"]
}

pub fn a_package_that_is_not_loaded_is_a_type_error_test() {
  let assert Run(outcome: shell.TypeFailed(_), ..) =
    run.run(fixture.shell(), fixture.tasks(), "@json")
}

pub fn tags_can_be_counted_test() {
  assert value(
      "let {list} = @standard
let tags = list.fold(list.flat_map(todos.all({}), todos.tags), [], (tag, seen) -> {
  match list.contains(seen, tag) {
    True(_) -> { seen }
    False(_) -> { [tag, ..seen] }
  }
})
list.map(tags, (tag) -> { {tag, count: list.length(todos.tagged(tag))} })",
    )
    == v.LinkedList([record("#work", 1), record("#shopping", 2)])
}

pub fn titles_can_be_rewritten_test() {
  let Run(tasks:, ..) =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let {list, string} = @standard
list.map(todos.matching(\"plumber\"), (task) -> { todos.rename(task, string.append(\"Urgent: \", task.title)) })",
    )
  let assert [_, Task(2, "Urgent: Call the plumber", False), ..] =
    tasks.all(tasks)
}

fn record(tag, count) {
  v.Record(
    dict.from_list([#("tag", v.String(tag)), #("count", v.Integer(count))]),
  )
}
