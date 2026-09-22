//// Evals give Jev a task and a starting program and loop until a checker
//// accepts the program or the step budget runs out.
//// Jev chooses from offered names and literals, so tasks name everything the
//// program needs and describe the approach.

import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev_playground/action
import jev_playground/agent
import jev_playground/compound
import jev_playground/dnsimple
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
    /// Accepts the program, or says what is wrong with it.
    check: fn(ir.Node(List(Int)), Environment) -> Result(Nil, String),
    /// The content id of a module the program has in scope as `context`, fetched from a hub.
    context: Option(String),
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
    /// In hole mode, how many holes are filled in one request.
    cursors: Int,
    jumps: Bool,
    highlight: options.Highlight,
    check_compounds: Bool,
    hole_jumps: Bool,
    context_compounds: options.ContextCompounds,
    effects: options.EffectsShown,
    /// Jev is shown what a program returns but not whether it is right.
    blind: Bool,
    context_readme: Bool,
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
  cursors: 1,
  jumps: True,
  highlight: options.Excerpt,
  check_compounds: False,
  hole_jumps: False,
  context_compounds: options.ContextCalls,
  effects: options.EffectSignatures,
  blind: False,
  context_readme: True,
)

/// Build a variant from flags, `compounds` adds all the mined compounds and
/// `compounds=5` the five most frequent, `instances=2` offers two instances of each,
/// `flat`, `untyped` and `repeats` turn improvements off, `holes` keeps the selection on holes, `types` lists the type of every hole
/// `cursors=3` asks what fills three holes at once, `nojumps` stops offering jumps to type errors
/// `mark=guillemets`, `mark=comments` or `mark=unmarked` changes how the selection is shown, the default is `excerpt`
/// `checked` only offers compound instances that apply without a new type error
/// `holejumps` offers to move to any hole by its number
/// `ctx=none` or `ctx=calls` sets how compounds are built from a context
/// `effects=hidden`, `signatures`, `calls`, `nodes` or `callsonly` sets how effects are shown
/// `blind` shows Jev what a program returns but not whether it is right
/// and `noreadme` leaves the readme of the context out of the state.
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
    cursors: number("cursors", 3) |> result.unwrap(1),
    jumps: !list.contains(flags, "nojumps"),
    highlight: list.find_map(flags, fn(flag) {
      case flag {
        "mark=" <> name -> options.highlight_from_name(name)
        _ -> Error(Nil)
      }
    })
      |> result.unwrap(improved.highlight),
    check_compounds: list.contains(flags, "checked"),
    hole_jumps: list.contains(flags, "holejumps"),
    context_compounds: list.find_map(flags, fn(flag) {
      case flag {
        "ctx=" <> name -> options.context_compounds_from_name(name)
        _ -> Error(Nil)
      }
    })
      |> result.unwrap(improved.context_compounds),
    effects: list.find_map(flags, fn(flag) {
      case flag {
        "effects=" <> name -> options.effects_from_name(name)
        _ -> Error(Nil)
      }
    })
      |> result.unwrap(improved.effects),
    blind: list.contains(flags, "blind"),
    context_readme: !list.contains(flags, "noreadme"),
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
    cursors:,
    jumps:,
    highlight:,
    check_compounds:,
    hole_jumps:,
    context_compounds:,
    effects:,
    blind:,
    context_readme:,
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
      #(cursors > 1, "cursors" <> int.to_string(cursors)),
      #(!jumps, "nojumps"),
      #(
        highlight != improved.highlight,
        "mark" <> options.highlight_name(highlight),
      ),
      #(check_compounds, "checked"),
      #(hole_jumps, "holejumps"),
      #(
        context_compounds != improved.context_compounds,
        "ctx" <> options.context_compounds_name(context_compounds),
      ),
      #(effects != improved.effects, "effects" <> options.effects_name(effects)),
      #(blind, "blind"),
      #(!context_readme, "noreadme"),
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
    cursors: variant.cursors,
    jumps: variant.jumps,
    highlight: variant.highlight,
    check_compounds: variant.check_compounds,
    hole_jumps: variant.hole_jumps,
    context_compounds: variant.context_compounds,
    effects: variant.effects,
    context_readme: variant.context_readme,
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
    ..dnsimple_questions()
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
      |> result.map(fn(tree) { action.todo_holes(e.from_annotated(tree)) })
      |> result.replace_error("the start of " <> eval.slug <> " does not parse")
  }
}

/// Run the checker against a program, reporting why it is not yet correct.
pub fn check(
  eval: Eval,
  source,
  environment: Environment,
) -> Result(Nil, String) {
  eval.check(source, environment)
}

/// A checker of the value a program without effects returns.
fn returns(check) {
  fn(source, environment) {
    use value <- result.try(
      run.evaluate(source, environment)
      |> result.map_error(fn(reason) { "the program does not run: " <> reason }),
    )
    check(value, environment)
  }
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
    context: None,
    check: returns(fn(value, environment) {
      [#(0, []), #(1, [0]), #(2, [0, 1]), #(6, [0, 1, 1, 2, 3, 5])]
      |> list.map(fn(case_) {
        #([v.Integer(case_.0)], v.LinkedList(list.map(case_.1, v.Integer)))
      })
      |> calls(value, environment, _)
    }),
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
    context: None,
    check: returns(fn(value, environment) {
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
    }),
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
    "dnsimple-" <> question -> dnsimple_solution(question)
    _ -> ""
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
    context: None,
    check: returns(fn(value, environment) {
      calls(value, environment, [
        #([v.String("Ada")], v.String("Hello, Ada")),
        #([v.String("")], v.String("Hello, ")),
      ])
    }),
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
    context: None,
    check: returns(fn(value, environment) {
      let record =
        v.Record(
          dict.from_list([#("name", v.String("Ada")), #("age", v.Integer(36))]),
        )
      calls(value, environment, [
        #([v.String("Ada"), v.Integer(36)], record),
      ])
    }),
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
    context: None,
    check: returns(fn(value, environment) {
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
    }),
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
    context: None,
    check: returns(fn(value, environment) {
      calls(value, environment, [
        #([v.ok(v.String("found"))], v.String("found")),
        #([v.error(v.unit())], v.String("unknown")),
      ])
    }),
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

pub type Verdict {
  Continue
  Solved
  /// Jev said it had finished, with a program the checker does not accept.
  FinishedWrong(reason: String)
}

/// With an oracle the checker stands in for tests: it runs when Jev runs the
/// tests, says it has finished or the program is complete, and says what is wrong.
/// Blind, Jev is only shown what a complete program returns, as a person would
/// see, and the eval is solved when Jev finishes with a program the checker accepts.
pub fn after_step(
  eval: Eval,
  variant: Variant,
  agent: agent.Agent,
  step: agent.Step,
) -> #(agent.Agent, Verdict) {
  let source = buffer.source(agent.buffer)
  let asked = case step.action {
    action.RunTests | action.Finish -> True
    _ -> False
  }
  case variant.blind, step.action {
    True, action.Finish ->
      case agent.is_complete(agent) {
        False -> {
          let results = option.Some("the program still has holes")
          #(
            agent.Agent(..agent, test_results: results, finished: False),
            Continue,
          )
        }
        True ->
          case check(eval, source, agent.environment) {
            Ok(Nil) -> #(agent, Solved)
            Error(reason) -> #(agent, FinishedWrong(reason))
          }
      }
    True, _ ->
      case asked || agent.is_complete(agent) {
        False -> #(agent, Continue)
        True -> {
          let results = option.Some(output(eval, source, agent.environment))
          #(agent.Agent(..agent, test_results: results), Continue)
        }
      }
    False, _ ->
      case asked || agent.is_complete(agent) {
        False -> #(agent, Continue)
        True ->
          case check(eval, source, agent.environment) {
            Ok(Nil) -> {
              let results =
                option.Some(
                  "1 of 1 tests passed, the checker accepted the program",
                )
              #(agent.Agent(..agent, test_results: results), Solved)
            }
            Error(reason) -> {
              let results =
                option.Some("The checker found a problem: " <> reason)
              #(
                agent.Agent(..agent, test_results: results, finished: False),
                Continue,
              )
            }
          }
      }
  }
}

/// What running a program shows a person, with no verdict on it.
pub fn output(eval: Eval, source, environment: Environment) -> String {
  let returned = case eval.context {
    Some(_) ->
      run.evaluate_handled(
        source,
        environment,
        dnsimple.fixture(),
        dnsimple.handle,
      )
      |> result.map(fn(pair) { pair.0 })
    None -> run.evaluate(source, environment)
  }
  case returned {
    Ok(value) -> "the program returned " <> simple_debug.inspect(value)
    Error(reason) -> "the program failed: " <> reason
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
  use cursors <- decode.optional_field("cursors", 1, decode.int)
  use jumps <- decode.optional_field("jumps", True, decode.bool)
  use check_compounds <- decode.optional_field(
    "check_compounds",
    False,
    decode.bool,
  )
  use hole_jumps <- decode.optional_field("hole_jumps", False, decode.bool)
  use blind <- decode.optional_field("blind", False, decode.bool)
  use context_readme <- decode.optional_field(
    "context_readme",
    True,
    decode.bool,
  )
  use effects <- decode.optional_field(
    "effects",
    options.EffectSignatures,
    decode.then(decode.string, fn(name) {
      case options.effects_from_name(name) {
        Ok(shown) -> decode.success(shown)
        Error(Nil) -> decode.failure(options.EffectSignatures, "EffectsShown")
      }
    }),
  )
  use context_compounds <- decode.optional_field(
    "context_compounds",
    options.ContextCalls,
    decode.then(decode.string, fn(name) {
      case options.context_compounds_from_name(name) {
        Ok(strategy) -> decode.success(strategy)
        Error(Nil) -> decode.failure(options.ContextCalls, "ContextCompounds")
      }
    }),
  )
  // Runs saved before the highlight was recorded marked the selection with « and ».
  use highlight <- decode.optional_field(
    "highlight",
    options.Guillemets,
    decode.then(decode.string, fn(name) {
      case options.highlight_from_name(name) {
        Ok(highlight) -> decode.success(highlight)
        Error(Nil) -> decode.failure(options.Guillemets, "Highlight")
      }
    }),
  )
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
      cursors:,
      jumps:,
      highlight:,
      check_compounds:,
      hole_jumps:,
      context_compounds:,
      effects:,
      blind:,
      context_readme:,
    )
  case find(slug) {
    Ok(eval) -> decode.success(Run(eval:, variant:, steps:, outcome:))
    Error(Nil) -> decode.failure(Run(fibonacci(), improved, [], ""), "eval")
  }
}

// Questions about a DNSimple account, answered from an empty program with the
// DNSimple context in scope. The context is fetched from a hub by content id.

fn question(slug, task, check) -> Eval {
  Eval(
    slug: "dnsimple-" <> slug,
    title: task,
    task:,
    start: "",
    open_libraries: [],
    max_steps: 30,
    check:,
    context: Some(dnsimple.context_id),
  )
}

/// Accepts a program that returns the answer. Jev is told what its program
/// returned but not the answer, as it would be when run for a person.
fn answers(expected: run.Value) {
  fn(source, environment) {
    case
      run.evaluate_handled(
        source,
        environment,
        dnsimple.fixture(),
        dnsimple.handle,
      )
    {
      Ok(#(value, _)) if value == expected -> Ok(Nil)
      Ok(#(value, _)) ->
        Error(
          "the program returned "
          <> simple_debug.inspect(value)
          <> ", which does not answer the question",
        )
      Error(reason) -> Error("the program failed: " <> reason)
    }
  }
}

/// Accepts a program that returns any of the answers.
fn answers_any(expected: List(run.Value)) {
  fn(source, environment) {
    case
      run.evaluate_handled(
        source,
        environment,
        dnsimple.fixture(),
        dnsimple.handle,
      )
    {
      Ok(#(value, _)) ->
        case list.contains(expected, value) {
          True -> Ok(Nil)
          False ->
            Error(
              "the program returned "
              <> simple_debug.inspect(value)
              <> ", which does not answer the question",
            )
        }
      Error(reason) -> Error("the program failed: " <> reason)
    }
  }
}

/// Accepts a program that makes a change to the account.
fn changes(missing: String, changed: fn(dnsimple.Account) -> Bool) {
  fn(source, environment) {
    case
      run.evaluate_handled(
        source,
        environment,
        dnsimple.fixture(),
        dnsimple.handle,
      )
    {
      Ok(#(_, account)) ->
        case changed(account) {
          True -> Ok(Nil)
          False -> Error("the program ran but " <> missing)
        }
      Error(reason) -> Error("the program failed: " <> reason)
    }
  }
}

fn records_of(domain: String, keep: fn(dnsimple.Record) -> Bool) {
  let assert Ok(domain) = dnsimple.find_domain(dnsimple.fixture(), domain)
  domain.records
  |> list.filter(keep)
  |> list.map(dnsimple.record_value)
  |> v.LinkedList
}

fn has_record(account, domain, keep: fn(dnsimple.Record) -> Bool) {
  case dnsimple.find_domain(account, domain) {
    Ok(domain) -> list.any(domain.records, keep)
    Error(Nil) -> False
  }
}

/// Twenty questions a person might ask of their account, easiest first.
pub fn dnsimple_questions() -> List(Eval) {
  let all_names = [
    "lovelace.dev", "analytical.engineering", "notes.garden", "babbage.org",
  ]
  [
    question(
      "domains",
      "What domains are in my DNSimple account?",
      answers_any([
        dnsimple.strings(all_names),
        v.LinkedList(list.map(dnsimple.fixture().domains, dnsimple.domain_value)),
      ]),
    ),
    question(
      "domain-count",
      "How many domains do I have?",
      answers(v.Integer(4)),
    ),
    question(
      "email",
      "What email address is my account registered to?",
      answers(v.String("ada@lovelace.dev")),
    ),
    question(
      "available",
      "Is jev-rocks.com available to register?",
      answers(v.true()),
    ),
    question(
      "name-servers",
      "Which name servers is notes.garden delegated to?",
      answers(dnsimple.strings(dnsimple.fixture().name_servers)),
    ),
    question(
      "records",
      "List the DNS records of analytical.engineering.",
      answers(records_of("analytical.engineering", fn(_) { True })),
    ),
    question(
      "record-count",
      "How many DNS records does lovelace.dev have?",
      answers(v.Integer(7)),
    ),
    question(
      "a-records",
      "What IP addresses do the A records of lovelace.dev point to?",
      answers(
        dnsimple.strings(["93.184.215.14", "93.184.215.15", "198.51.100.1"]),
      ),
    ),
    question(
      "mx",
      "What are the MX records of analytical.engineering?",
      answers(records_of("analytical.engineering", fn(r) { r.type_ == "MX" })),
    ),
    question(
      "no-renew",
      "Which of my domains will not renew automatically?",
      answers(
        dnsimple.strings([
          "analytical.engineering",
          "notes.garden",
          "babbage.org",
        ]),
      ),
    ),
    question(
      "expiry",
      "When does notes.garden expire?",
      answers(v.String("2028-01-02")),
    ),
    question(
      "expiring",
      "Which of my domains expire before 2027-06-01?",
      answers(dnsimple.strings(["lovelace.dev", "analytical.engineering"])),
    ),
    question(
      "a-count",
      "How many A records does lovelace.dev have?",
      answers(v.Integer(3)),
    ),
    question(
      "add-txt",
      "Add a TXT record to lovelace.dev with the content \"google-site-verification=abc123\".",
      changes("lovelace.dev has no such TXT record", fn(account) {
        has_record(account, "lovelace.dev", fn(r) {
          r.type_ == "TXT"
          && r.name == ""
          && r.content == "google-site-verification=abc123"
        })
      }),
    ),
    question(
      "point-www",
      "Point www.notes.garden at 203.0.113.7 with an A record.",
      changes("notes.garden has no such A record for www", fn(account) {
        has_record(account, "notes.garden", fn(r) {
          r.type_ == "A" && r.name == "www" && r.content == "203.0.113.7"
        })
      }),
    ),
    question(
      "remove-old",
      "Delete the TXT record named \"old\" from lovelace.dev.",
      changes("the TXT record named old is still there", fn(account) {
        !has_record(account, "lovelace.dev", fn(r) {
          r.type_ == "TXT" && r.name == "old"
        })
      }),
    ),
    question(
      "auto-renew",
      "Turn on auto-renew for notes.garden.",
      changes("notes.garden still does not renew", fn(account) {
        case dnsimple.find_domain(account, "notes.garden") {
          Ok(domain) -> domain.auto_renew
          Error(Nil) -> False
        }
      }),
    ),
    question(
      "change-api",
      "Change the A record of api.lovelace.dev to 198.51.100.4.",
      changes("api.lovelace.dev does not point at 198.51.100.4", fn(account) {
        has_record(account, "lovelace.dev", fn(r) {
          r.type_ == "A" && r.name == "api" && r.content == "198.51.100.4"
        })
      }),
    ),
    question(
      "total-records",
      "How many DNS records do I have across all of my domains?",
      answers(v.Integer(14)),
    ),
    question(
      "every-record",
      "List every DNS record in my account.",
      answers(
        list.flat_map(all_names, fn(name) {
          let assert v.LinkedList(records) = records_of(name, fn(_) { True })
          records
        })
        |> v.LinkedList,
      ),
    ),
  ]
}

fn dnsimple_solution(question) {
  case question {
    "domains" -> "context.domain_names({})"
    "domain-count" -> "context.count(context.domain_names({}))"
    "email" -> "context.account({}).email"
    "available" -> "context.is_available(\"jev-rocks.com\")"
    "name-servers" -> "context.name_servers(\"notes.garden\")"
    "records" -> "context.records(\"analytical.engineering\")"
    "record-count" -> "context.count(context.records(\"lovelace.dev\"))"
    "a-records" -> "context.record_values(\"lovelace.dev\", \"A\")"
    "mx" -> "context.records_of_type(\"analytical.engineering\", \"MX\")"
    "no-renew" -> "context.without_auto_renew({})"
    "expiry" -> "context.domain(\"notes.garden\").expires_on"
    "expiring" -> "context.expiring_before(\"2027-06-01\")"
    "a-count" ->
      "context.count(context.records_of_type(\"lovelace.dev\", \"A\"))"
    "add-txt" ->
      "context.add_record(\"lovelace.dev\", \"\", \"TXT\", \"google-site-verification=abc123\")"
    "point-www" ->
      "context.add_record(\"notes.garden\", \"www\", \"A\", \"203.0.113.7\")"
    "remove-old" -> "context.remove_record(\"lovelace.dev\", \"old\", \"TXT\")"
    "auto-renew" -> "context.enable_auto_renew(\"notes.garden\")"
    "change-api" ->
      "context.change_record(\"lovelace.dev\", \"api\", \"A\", \"198.51.100.4\")"
    "total-records" ->
      "context.count(context.flatten(context.map(context.domain_names({}), context.records)))"
    "every-record" ->
      "context.flatten(context.map(context.domain_names({}), context.records))"
    _ -> ""
  }
}
