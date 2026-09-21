//// Evals give Jev a task and a starting program and loop until a checker
//// accepts the program or the step budget runs out.
//// Jev chooses from offered names and literals, so tasks name everything the
//// program needs and describe the approach.

import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/compound
import jev_playground/environment.{type Environment}
import jev_playground/options
import jev_playground/run
import morph/buffer
import morph/editable as e

pub type Eval {
  Eval(
    slug: String,
    title: String,
    task: String,
    start: String,
    open_libraries: List(String),
    max_steps: Int,
    check: fn(run.Value, Environment) -> Result(Nil, String),
  )
}

/// How the options are offered, the variables compared by running evals.
pub type Variant {
  Variant(
    compounds: Bool,
    slot_questions: Bool,
    type_filter: Bool,
    no_repeats: Bool,
    focus_holes: Bool,
  )
}

/// The default variant, every improvement on and no compounds.
pub const improved = Variant(
  compounds: False,
  slot_questions: True,
  type_filter: True,
  no_repeats: True,
  focus_holes: False,
)

/// Build a variant from flags, `compounds` adds compounds and
/// `flat`, `untyped` and `repeats` turn improvements off, `holes` keeps the selection on holes.
pub fn variant(flags: List(String)) -> Variant {
  Variant(
    compounds: list.contains(flags, "compounds"),
    slot_questions: !list.contains(flags, "flat"),
    type_filter: !list.contains(flags, "untyped"),
    no_repeats: !list.contains(flags, "repeats"),
    focus_holes: list.contains(flags, "holes"),
  )
}

pub fn variant_name(variant: Variant) {
  let Variant(
    compounds:,
    slot_questions:,
    type_filter:,
    no_repeats:,
    focus_holes:,
  ) = variant
  let flags =
    [
      #(compounds, "compounds"),
      #(!slot_questions, "flat"),
      #(!type_filter, "untyped"),
      #(!no_repeats, "repeats"),
      #(focus_holes, "holes"),
    ]
    |> list.filter_map(fn(flag) {
      case flag.0 {
        True -> Ok(flag.1)
        False -> Error(Nil)
      }
    })
  case flags {
    [] -> "improved"
    _ -> string.join(flags, "-")
  }
}

pub fn config(eval: Eval, variant: Variant) -> options.Config {
  options.Config(
    ..options.default_config(),
    open_libraries: eval.open_libraries,
    compounds: case variant.compounds {
      True -> compound.mined()
      False -> []
    },
    slot_questions: variant.slot_questions,
    type_filter: variant.type_filter,
    no_repeats: variant.no_repeats,
    focus_holes: variant.focus_holes,
  )
}

pub fn all() -> List(Eval) {
  [
    fibonacci(),
    list_functions(),
    fibonacci_scaffold(),
    list_functions_scaffold(),
  ]
}

pub fn find(slug) {
  list.find(all(), fn(eval) { eval.slug == slug })
}

pub fn start(eval: Eval) -> Result(e.Expression, String) {
  case eval.start {
    "" -> Ok(e.Vacant)
    source ->
      parser.all_from_string(source)
      |> result.map(fn(tree) { holes(e.from_annotated(tree)) })
      |> result.replace_error("the start of " <> eval.slug <> " does not parse")
  }
}

/// Run the checker against a program, reporting why it is not yet correct.
pub fn check(
  eval: Eval,
  source,
  environment: Environment,
) -> Result(Nil, String) {
  use value <- result.try(
    run.evaluate(source, environment)
    |> result.map_error(fn(reason) { "the program does not run: " <> reason }),
  )
  eval.check(value, environment)
}

const standard = "@standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja"

pub fn fibonacci() {
  Eval(
    slug: "fibonacci",
    title: "First n Fibonacci numbers",
    task: "Write a function `(n)` returning a list of the first `n` Fibonacci numbers starting 0, 1, for 6 it returns [0, 1, 1, 2, 3, 5].
First destructure `{list}` from @standard, then define `fibonacci = (n)`, the program ends with `fibonacci`.
In it define `go` as `!fix` of `(go, count, a, b, acc)`: match `!int_compare` of `count` and 0, when `Gt` call `go` with `!int_subtract` of `count` and 1, then `b`, then `!int_add` of `a` and `b`, then `list.append` of `acc` and the list `[a]`, otherwise return `acc`.
The function returns `go(n, 0, 1, [])`.",
    start: "",
    open_libraries: ["standard"],
    max_steps: 160,
    check: fn(value, environment) {
      list.try_each(
        [#(0, []), #(1, [0]), #(2, [0, 1]), #(6, [0, 1, 1, 2, 3, 5])],
        fn(case_) {
          let #(n, expected) = case_
          let expected = v.LinkedList(list.map(expected, v.Integer))
          case run.call(value, [v.Integer(n)], environment) {
            Ok(got) if got == expected -> Ok(Nil)
            Ok(got) ->
              Error(
                "for "
                <> int.to_string(n)
                <> " it returned "
                <> simple_debug.inspect(got)
                <> " not "
                <> simple_debug.inspect(expected),
              )
            Error(reason) ->
              Error("for " <> int.to_string(n) <> " it failed: " <> reason)
          }
        },
      )
    },
  )
}

pub fn list_functions() {
  Eval(
    slug: "list-functions",
    title: "Add functions to a list library",
    task: "This list library built on @standard has `length`. Add two functions above the exported record.
`sum = (items)` is `list.fold` of `items`, 0 and `!int_add`.
`last = (items)` is `list.head` of `list.reverse` of `items`.
Export them too, the record becomes `{length, sum, last}`.",
    start: "let {list} = " <> standard <> "
let length = (items) -> { list.fold(items, 0, (item, count) -> { !int_add(count, 1) }) }
{length}",
    open_libraries: ["standard"],
    max_steps: 120,
    check: fn(value, environment) {
      let numbers = v.LinkedList([v.Integer(1), v.Integer(2), v.Integer(3)])
      let empty = v.LinkedList([])
      use fields <- result.try(case value {
        v.Record(fields) -> Ok(fields)
        _ -> Error("the program is not a record")
      })
      list.try_each(
        [
          #("length", numbers, v.Integer(3)),
          #("sum", numbers, v.Integer(6)),
          #("sum", empty, v.Integer(0)),
          #("last", numbers, v.Tagged("Ok", v.Integer(3))),
          #("last", empty, v.Tagged("Error", v.unit())),
        ],
        fn(case_) {
          let #(name, input, expected) = case_
          use func <- result.try(
            dict.get(fields, name)
            |> result.replace_error("the record has no `" <> name <> "`"),
          )
          case run.call(func, [input], environment) {
            Ok(got) if got == expected -> Ok(Nil)
            Ok(got) ->
              Error(
                name
                <> " of "
                <> simple_debug.inspect(input)
                <> " returned "
                <> simple_debug.inspect(got)
                <> " not "
                <> simple_debug.inspect(expected),
              )
            Error(reason) -> Error(name <> " failed: " <> reason)
          }
        },
      )
    },
  )
}

/// The program each eval should reach, used to check the checker.
pub fn solution(eval: Eval) -> String {
  case eval.slug {
    "fibonacci" | "fibonacci-scaffold" -> "let {list} = " <> standard <> "
let fibonacci = (n) -> {
  let go = !fix((go, count, a, b, acc) -> {
    match !int_compare(count, 0) {
      Gt(_) -> { go(!int_subtract(count, 1), b, !int_add(a, b), list.append(acc, [a])) }
      | (_) -> { acc }
    }
  })
  go(n, 0, 1, [])
}
fibonacci"
    "list-functions" | "list-functions-scaffold" ->
      string.replace(
        list_functions().start,
        "{length}",
        "let sum = (items) -> { list.fold(items, 0, !int_add) }
let last = (items) -> { list.head(list.reverse(items)) }
{length, sum, last}",
      )
    _ -> ""
  }
}

/// Holes have no syntax, a scaffold marks them with the variable `todo`.
pub fn holes(source: e.Expression) -> e.Expression {
  case source {
    e.Variable("todo") -> e.Vacant
    e.Block(assigns, then, open) ->
      e.Block(
        list.map(assigns, fn(assign) { #(assign.0, holes(assign.1)) }),
        holes(then),
        open,
      )
    e.Call(func, args) -> e.Call(holes(func), list.map(args, holes))
    e.Function(params, body) -> e.Function(params, holes(body))
    e.List(items, tail) ->
      e.List(list.map(items, holes), option.map(tail, holes))
    e.Record(fields, original) ->
      e.Record(
        list.map(fields, fn(field) { #(field.0, holes(field.1)) }),
        option.map(original, holes),
      )
    e.Select(from, label) -> e.Select(holes(from), label)
    e.Case(top, matches, otherwise) ->
      e.Case(
        holes(top),
        list.map(matches, fn(match) { #(match.0, holes(match.1)) }),
        option.map(otherwise, holes),
      )
    _ -> source
  }
}

/// Fibonacci with its structure written, Jev fills the three holes.
pub fn fibonacci_scaffold() {
  Eval(
    ..fibonacci(),
    slug: "fibonacci-scaffold",
    title: "First n Fibonacci numbers from a scaffold",
    task: "Fill the three holes in this function returning the first `n` Fibonacci numbers starting 0, 1, for 6 it returns [0, 1, 1, 2, 3, 5].
1. The `Gt` branch is a call to `go` with four arguments: `!int_subtract(count, 1)`, `b`, `!int_add(a, b)` and `list.append(acc, [a])`.
2. The otherwise branch is `acc`.
3. The function returns the call `go(n, 0, 1, [])`.",
    start: "let {list} = " <> standard <> "
let fibonacci = (n) -> {
  let go = !fix((go, count, a, b, acc) -> {
    match !int_compare(count, 0) {
      Gt(_) -> { todo }
      | (_) -> { todo }
    }
  })
  todo
}
fibonacci",
    max_steps: 80,
  )
}

/// The list functions with their definitions started, Jev fills the bodies.
pub fn list_functions_scaffold() {
  Eval(
    ..list_functions(),
    slug: "list-functions-scaffold",
    title: "Add functions to a list library from a scaffold",
    task: "This list library built on @standard has `length`, fill in the new functions.
`sum = (items)` is `list.fold` of `items`, 0 and `!int_add`.
`last = (items)` is `list.head` of `list.reverse` of `items`.",
    start: "let {list} = " <> standard <> "
let length = (items) -> { list.fold(items, 0, (item, count) -> { !int_add(count, 1) }) }
let sum = (items) -> { todo }
let last = (items) -> { todo }
{length, sum, last}",
    max_steps: 80,
  )
}

/// The checker stands in for tests: it runs when Jev runs the tests, when Jev
/// says it has finished and whenever the program is complete.
/// Returns the agent, with any problem shown as test results, and whether it is solved.
pub fn after_step(eval: Eval, agent: agent.Agent, step: agent.Step) {
  let asked = case step.action {
    action.RunTests | action.Finish -> True
    _ -> False
  }
  case asked || agent.is_complete(agent) {
    False -> #(agent, False)
    True ->
      case check(eval, buffer.source(agent.buffer), agent.environment) {
        Ok(Nil) -> {
          let results =
            option.Some("1 of 1 tests passed, the checker accepted the program")
          #(agent.Agent(..agent, test_results: results), True)
        }
        Error(reason) -> {
          let results = option.Some("The checker found a problem: " <> reason)
          #(agent.Agent(..agent, test_results: results, finished: False), False)
        }
      }
  }
}

/// A saved run of an eval.
pub type Run {
  Run(eval: Eval, variant: Variant, steps: List(agent.Step), outcome: String)
}

pub fn run_decoder() -> decode.Decoder(Run) {
  use slug <- decode.field("eval", decode.string)
  use compounds <- decode.field("compounds", decode.bool)
  use slot_questions <- decode.field("slot_questions", decode.bool)
  use type_filter <- decode.optional_field("type_filter", True, decode.bool)
  use no_repeats <- decode.optional_field("no_repeats", True, decode.bool)
  use focus_holes <- decode.optional_field("focus_holes", False, decode.bool)
  use steps <- decode.field("steps", decode.list(agent.step_decoder()))
  use outcome <- decode.field("outcome", decode.string)
  let variant =
    Variant(
      compounds:,
      slot_questions:,
      type_filter:,
      no_repeats:,
      focus_holes:,
    )
  case find(slug) {
    Ok(eval) -> decode.success(Run(eval:, variant:, steps:, outcome:))
    Error(Nil) -> decode.failure(Run(fibonacci(), improved, [], ""), "eval")
  }
}
