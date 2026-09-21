import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jev
import jev_playground/action as a
import jev_playground/agent
import jev_playground/environment
import jev_playground/options
import morph/editable as e

fn new(task) {
  agent.new(task, e.Vacant, environment.pure(), options.default_config())
}

fn keys(agent) {
  list.map(agent.options(agent), options.key)
}

fn take_all(agent, actions) {
  list.fold(actions, agent, fn(agent, action) {
    let assert Ok(agent) = agent.take(agent, agent.scripted(action))
    agent
  })
}

pub fn empty_program_offers_values_and_structure_test() {
  let keys = keys(new("Add `n` to 1"))
  assert list.contains(keys, "function (?) ->")
  assert list.contains(keys, "integer 1")
  assert list.contains(keys, "builtin !int_add")
  assert list.contains(keys, "let ? =")
  assert list.contains(
    agent.candidates(new("Add `n` to 1"), options.NameSlot),
    "n",
  )
  assert !list.contains(keys, "move next")
}

pub fn strings_in_the_task_are_offered_test() {
  let keys = keys(new("Return \"hello world\""))
  assert list.contains(keys, "string \"hello world\"")
}

pub fn variables_in_scope_are_offered_test() {
  let agent = take_all(new("inc `n`"), [a.Function("n")])
  assert agent.program_text(agent) == "(n) -> { «?» }"
  assert list.contains(keys(agent), "variable n")
}

pub fn choosing_the_selected_variable_again_moves_on_test() {
  let agent =
    take_all(new("`{a, b}` of `n`"), [
      a.Function("n"),
      a.Record(["a", "b"]),
      a.Variable("n"),
    ])
  assert agent.program_text(agent) == "(n) -> { {a: «n», b: ?} }"
  let agent = take_all(agent, [a.Variable("n")])
  assert agent.program_text(agent) == "(n) -> { {a: n, b: «?»} }"
}

pub fn a_program_is_built_one_edit_at_a_time_test() {
  let agent =
    take_all(new("inc `n`"), [
      a.Function("n"),
      a.Builtin("int_add"),
      a.Call,
      a.Variable("n"),
      a.Integer(1),
    ])
  assert agent.program_text(agent) == "(n) -> { !int_add(n, «1») }"
  assert agent.is_complete(agent)
}

pub fn navigation_moves_the_selection_test() {
  let agent =
    take_all(new("inc `n`"), [a.Function("n"), a.Builtin("int_add"), a.Call])
  assert agent.program_text(agent) == "(n) -> { !int_add(«?», ?) }"
  let agent = take_all(agent, [a.Next])
  assert agent.program_text(agent) == "(n) -> { !int_add(?, «?») }"
  let agent = take_all(agent, [a.Parent])
  assert agent.program_text(agent) == "(n) -> { «!int_add(?, ?)» }"
}

pub fn type_errors_can_be_jumped_to_test() {
  let agent =
    take_all(new("add"), [
      a.Builtin("int_add"),
      a.Call,
      a.String("x"),
      a.Integer(1),
    ])
  assert agent.type_error_count(agent) == 1
  assert list.contains(keys(agent), "jump to type error 1")
  let agent = take_all(agent, [a.JumpToError(0)])
  assert string.contains(agent.program_text(agent), "«")
}

pub fn jumps_can_be_turned_off_test() {
  let config = options.Config(..options.default_config(), jumps: False)
  let agent =
    agent.new("add", e.Vacant, environment.pure(), config)
    |> take_all([a.Builtin("int_add"), a.Call, a.String("x"), a.Integer(1)])
  assert agent.type_error_count(agent) == 1
  assert !list.contains(keys(agent), "jump to type error 1")
  assert list.contains(keys(agent), "move previous")
}

pub fn run_tests_reports_results_test() {
  let source =
    e.Record(
      [
        #(
          "tests",
          e.List(
            [
              e.Record(
                [
                  #("name", e.String("equal")),
                  #(
                    "test",
                    e.Function(
                      [e.Bind("_")],
                      e.Call(e.Builtin("equal"), [e.Integer(1), e.Integer(1)]),
                    ),
                  ),
                ],
                None,
              ),
            ],
            None,
          ),
        ),
      ],
      None,
    )
  let agent =
    agent.new("test", source, environment.pure(), options.default_config())
  let assert Ok(agent) = agent.take(agent, agent.scripted(a.RunTests))
  assert agent.test_results == Some("1 of 1 tests passed")
}

pub fn request_offers_every_option_as_a_choice_test() {
  let #(request, offered) = agent.request(new("inc `n`"), jev.latest)
  let assert [#("next_edit", jev.Choice(criteria:, ..)), ..] = request.questions
  let assert Ok(names) = list.key_find(request.questions, "name")
  assert list.length(criteria) == list.length(offered)
  let assert jev.Choice(criteria: names, ..) = names
  assert list.contains(names, #("n", None))
  let state = json.to_string(request.state)
  assert string.contains(state, "\"program\":\"«?»\"")
  assert string.contains(state, "\"task\":\"inc `n`\"")
}

pub fn answer_applies_the_chosen_option_test() {
  let agent = new("inc `n`")
  let #(_request, offered) = agent.request(agent, jev.latest)
  let answer =
    jev.ChoiceAnswer(
      "function (?) ->",
      dict.from_list([#("function (?) ->", 0.9), #("integer 1", 0.1)]),
      0.8,
    )
  let name = jev.ChoiceAnswer("n", dict.from_list([#("n", 1.0)]), 1.0)
  let evaluation =
    jev.Evaluation(
      "jev-1.13.0",
      dict.from_list([#("next_edit", answer), #("name", name)]),
      jev.Usage(100, 1),
    )
  let assert Ok(agent) = agent.answer(agent, offered, evaluation, 50)
  assert agent.program_text(agent) == "(n) -> { «?» }"
  let assert [step] = agent.history
  assert step.thinking_ms == 50
  assert step.ranked == [#("function (?) ->", 0.9), #("integer 1", 0.1)]
  assert step.label == "function (n) ->"
}

pub fn holes_can_be_listed_with_their_types_test() {
  let config = options.Config(..options.default_config(), hole_types: True)
  let agent =
    agent.new("inc `n`", e.Vacant, environment.pure(), config)
    |> take_all([a.Function("n"), a.Builtin("int_add"), a.Call])
  assert agent.program_text(agent) == "(n) -> { !int_add(«?», ?) }"
  assert list.length(a.holes(agent.buffer)) == 2
  let state = json.to_string(agent.state(agent))
  assert string.contains(
    state,
    "\"holes\":[\"1 (selected): Integer\",\"2: Integer\"]",
  )
}

pub fn several_holes_are_filled_in_one_request_test() {
  let config =
    options.Config(..options.default_config(), focus_holes: True, cursors: 2)
  let agent =
    agent.new("inc `n` by 1", e.Vacant, environment.pure(), config)
    |> take_all([a.Function("n"), a.Builtin("int_add"), a.Call])
  assert agent.program_text(agent) == "(n) -> { !int_add(«?», ⟨2:?⟩) }"
  let #(request, offered) = agent.request(agent, jev.latest)
  let assert Ok(jev.Choice(criteria:, ..)) =
    list.key_find(request.questions, "hole_2")
  let keys = list.map(criteria, fn(criterion) { criterion.0 })
  assert list.contains(keys, "leave it for later")
  assert list.contains(keys, "integer 1")
  let choose = fn(key) {
    jev.ChoiceAnswer(key, dict.from_list([#(key, 1.0)]), 1.0)
  }
  let evaluation =
    jev.Evaluation(
      "jev-1.13.0",
      dict.from_list([
        #("next_edit", choose("variable n")),
        #("hole_2", choose("integer 1")),
      ]),
      jev.Usage(100, 1),
    )
  let assert Ok(agent) = agent.answer(agent, offered, evaluation, 50)
  assert agent.program_text(agent) == "(n) -> { !int_add(n, «1») }"
  let assert [extra, main, ..] = agent.history
  assert main.input_tokens == 100
  assert extra.label == "at hole 2: integer 1"
  assert extra.input_tokens == 0
}

pub fn the_selection_can_be_shown_in_comments_or_only_described_test() {
  let state = fn(highlight) {
    let config = options.Config(..options.default_config(), highlight:)
    agent.new("inc `n`", e.Vacant, environment.pure(), config)
    |> take_all([a.Function("n"), a.Integer(1)])
    |> agent.state
    |> json.to_string
  }
  assert string.contains(
    state(options.Comments),
    "\"program\":\"(n) -> { /* selection */ 1 /* end */ }\"",
  )
  let unmarked = state(options.Unmarked)
  assert string.contains(unmarked, "\"program\":\"(n) -> { 1 }\"")
  assert string.contains(unmarked, "\"code\":\"1\"")
}
