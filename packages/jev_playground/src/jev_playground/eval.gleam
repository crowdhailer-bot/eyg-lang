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
    /// How many of the mined compounds are offered, most frequent first.
    compounds: Int,
    /// The most instances of each compound offered at a time.
    instances: Int,
    slot_questions: Bool,
    type_filter: Bool,
    no_repeats: Bool,
    focus_holes: Bool,
    hole_types: Bool,
  )
}

/// The default variant, every improvement on and no compounds.
pub const improved = Variant(
  compounds: 0,
  instances: 5,
  slot_questions: True,
  type_filter: True,
  no_repeats: True,
  focus_holes: False,
  hole_types: False,
)

/// Build a variant from flags, `compounds` adds all the mined compounds and
/// `compounds=5` the five most frequent, `instances=2` offers two instances of each,
/// `flat`, `untyped` and `repeats` turn improvements off, `holes` keeps the selection on holes, `types` lists the type of every hole.
pub fn variant(flags: List(String)) -> Variant {
  let number = fn(prefix, default) {
    list.find_map(flags, fn(flag) {
      case flag == prefix, string.split_once(flag, "=") {
        True, _ -> Ok(default)
        _, Ok(#(name, value)) if name == prefix -> int.parse(value)
        _, _ -> Error(Nil)
      }
    })
  }
  Variant(
    compounds: number("compounds", list.length(compound.mined()))
      |> result.unwrap(0),
    instances: number("instances", improved.instances)
      |> result.unwrap(improved.instances),
    slot_questions: !list.contains(flags, "flat"),
    type_filter: !list.contains(flags, "untyped"),
    no_repeats: !list.contains(flags, "repeats"),
    focus_holes: list.contains(flags, "holes"),
    hole_types: list.contains(flags, "types"),
  )
}

pub fn variant_name(variant: Variant) {
  let Variant(
    compounds:,
    instances:,
    slot_questions:,
    type_filter:,
    no_repeats:,
    focus_holes:,
    hole_types:,
  ) = variant
  let all = list.length(compound.mined())
  let flags =
    [
      #(compounds == all, "compounds"),
      #(
        compounds > 0 && compounds != all,
        "compounds" <> int.to_string(compounds),
      ),
      #(
        compounds > 0 && instances != improved.instances,
        "instances" <> int.to_string(instances),
      ),
      #(!slot_questions, "flat"),
      #(!type_filter, "untyped"),
      #(!no_repeats, "repeats"),
      #(focus_holes, "holes"),
      #(hole_types, "types"),
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
    compounds: list.take(compound.mined(), variant.compounds),
    compound_instances: variant.instances,
    slot_questions: variant.slot_questions,
    type_filter: variant.type_filter,
    no_repeats: variant.no_repeats,
    focus_holes: variant.focus_holes,
    hole_types: variant.hole_types,
  )
}

pub fn all() -> List(Eval) {
  [
    fibonacci(),
    list_functions(),
    fibonacci_scaffold(),
    list_functions_scaffold(),
    greeting(),
    greeting_scaffold(),
    user_record_scaffold(),
    total_scaffold(),
    describe_scaffold(),
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
      [#(0, []), #(1, [0]), #(2, [0, 1]), #(6, [0, 1, 1, 2, 3, 5])]
      |> list.map(fn(case_) {
        #([v.Integer(case_.0)], v.LinkedList(list.map(case_.1, v.Integer)))
      })
      |> calls(value, environment, _)
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
    "greeting" | "greeting-scaffold" -> "let {string} = " <> standard <> "
let greet = (name) -> { string.append(\"Hello, \", name) }
greet"
    "user-record-scaffold" ->
      "let user = (name, age) -> { {name: name, age: age} }
user"
    "total-scaffold" -> "let {list} = " <> standard <> "
let total = (items) -> {
  list.fold(items, 0, (item, sum) -> { !int_add(sum, !int_multiply(item.price, item.quantity)) })
}
total"
    "describe-scaffold" ->
      "let describe = (result) -> {
  match result {
    Ok(value) -> { value }
    Error(reason) -> { \"unknown\" }
  }
}
describe"
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

/// A function written from nothing, the smallest plan.
pub fn greeting() {
  Eval(
    slug: "greeting",
    title: "Greet by name",
    task: "Write a function `(name)` returning \"Hello, \" followed by the name, for \"Ada\" it returns \"Hello, Ada\".
First destructure `{string}` from @standard, then define `greet = (name)`, the program ends with `greet`.
The function returns `string.append` of \"Hello, \" and `name`.",
    start: "",
    open_libraries: ["standard"],
    max_steps: 60,
    check: fn(value, environment) {
      calls(value, environment, [
        #([v.String("Ada")], v.String("Hello, Ada")),
        #([v.String("")], v.String("Hello, ")),
      ])
    },
  )
}

/// One hole filled with a call taking a string literal.
pub fn greeting_scaffold() {
  Eval(
    ..greeting(),
    slug: "greeting-scaffold",
    title: "Greet by name from a scaffold",
    task: "Fill the hole so `greet` returns `string.append` of \"Hello, \" and `name`, for \"Ada\" it returns \"Hello, Ada\".",
    start: "let {string} = " <> standard <> "
let greet = (name) -> { todo }
greet",
    max_steps: 40,
  )
}

/// One hole filled with a record.
pub fn user_record_scaffold() {
  Eval(
    slug: "user-record-scaffold",
    title: "Build a record from a scaffold",
    task: "Fill the hole so `user` returns the record `{name: name, age: age}`.",
    start: "let user = (name, age) -> { todo }
user",
    open_libraries: [],
    max_steps: 40,
    check: fn(value, environment) {
      let record =
        v.Record(
          dict.from_list([#("name", v.String("Ada")), #("age", v.Integer(36))]),
        )
      calls(value, environment, [
        #([v.String("Ada"), v.Integer(36)], record),
      ])
    },
  )
}

/// One hole filled with nested builtin calls and field selections.
pub fn total_scaffold() {
  Eval(
    slug: "total-scaffold",
    title: "Total an order from a scaffold",
    task: "Each item is a record with a `price` and a `quantity`, `total` folds over the items.
Fill the hole with `!int_add` of `sum` and `!int_multiply` of `item.price` and `item.quantity`.",
    start: "let {list} = " <> standard <> "
let total = (items) -> { list.fold(items, 0, (item, sum) -> { todo }) }
total",
    open_libraries: ["standard"],
    max_steps: 60,
    check: fn(value, environment) {
      let item = fn(price, quantity) {
        v.Record(
          dict.from_list([
            #("price", v.Integer(price)),
            #("quantity", v.Integer(quantity)),
          ]),
        )
      }
      calls(value, environment, [
        #([v.LinkedList([])], v.Integer(0)),
        #([v.LinkedList([item(2, 3), item(5, 1)])], v.Integer(11)),
      ])
    },
  )
}

/// Two holes in the branches of a match.
pub fn describe_scaffold() {
  Eval(
    slug: "describe-scaffold",
    title: "Describe a result from a scaffold",
    task: "Fill the two holes in `describe`, when the result is `Ok` it returns `value`, when it is `Error` it returns the string \"unknown\".",
    start: "let describe = (result) -> {
  match result {
    Ok(value) -> { todo }
    Error(reason) -> { todo }
  }
}
describe",
    open_libraries: [],
    max_steps: 40,
    check: fn(value, environment) {
      calls(value, environment, [
        #([v.ok(v.String("found"))], v.String("found")),
        #([v.error(v.unit())], v.String("unknown")),
      ])
    },
  )
}

/// Call a function with each list of arguments and compare what it returns.
fn calls(
  value: run.Value,
  environment: Environment,
  cases: List(#(List(run.Value), run.Value)),
) -> Result(Nil, String) {
  list.try_each(cases, fn(case_) {
    let #(args, expected) = case_
    let shown = string.join(list.map(args, simple_debug.inspect), ", ")
    case run.call(value, args, environment) {
      Ok(got) if got == expected -> Ok(Nil)
      Ok(got) ->
        Error(
          "for ("
          <> shown
          <> ") it returned "
          <> simple_debug.inspect(got)
          <> " not "
          <> simple_debug.inspect(expected),
        )
      Error(reason) -> Error("for (" <> shown <> ") it failed: " <> reason)
    }
  })
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
  // Early runs recorded whether all the compounds were offered.
  use compounds <- decode.field(
    "compounds",
    decode.one_of(decode.int, [
      decode.bool
      |> decode.map(fn(all) {
        case all {
          True -> list.length(compound.mined())
          False -> 0
        }
      }),
    ]),
  )
  use instances <- decode.optional_field(
    "instances",
    improved.instances,
    decode.int,
  )
  use slot_questions <- decode.field("slot_questions", decode.bool)
  use type_filter <- decode.optional_field("type_filter", True, decode.bool)
  use no_repeats <- decode.optional_field("no_repeats", True, decode.bool)
  use focus_holes <- decode.optional_field("focus_holes", False, decode.bool)
  use hole_types <- decode.optional_field("hole_types", False, decode.bool)
  use steps <- decode.field("steps", decode.list(agent.step_decoder()))
  use outcome <- decode.field("outcome", decode.string)
  let variant =
    Variant(
      compounds:,
      instances:,
      slot_questions:,
      type_filter:,
      no_repeats:,
      focus_holes:,
      hole_types:,
    )
  case find(slug) {
    Ok(eval) -> decode.success(Run(eval:, variant:, steps:, outcome:))
    Error(Nil) -> decode.failure(Run(fibonacci(), improved, [], ""), "eval")
  }
}
