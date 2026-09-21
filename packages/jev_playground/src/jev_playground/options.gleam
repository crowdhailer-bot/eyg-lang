//// The actions available at the current focus, each with a description for Jev.
//// Availability is checked once per kind of action without applying it,
//// so offering many names does not require reanalysing the program for each.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import jev_playground/action.{type Action} as a
import jev_playground/environment.{type Environment}
import jev_playground/vocabulary.{type Vocabulary}
import morph/analysis
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/projection as p
import morph/text

pub type Option {
  Option(action: Action, name: String, description: String)
}

pub type Config {
  Config(
    /// Libraries whose API has been opened and can be referenced.
    open_libraries: List(String),
    /// Compound moves, abstract actions whose names and literals are filled from context.
    compounds: List(List(Action)),
    /// Offer to open libraries that are not yet open.
    search_libraries: Bool,
    /// Move to the next `?` after filling one with a complete value.
    advance: Bool,
    /// Ask for names and labels in separate questions rather than offering an edit for each.
    slot_questions: Bool,
    /// Only offer values whose type fits the hole, or whose result fits when called.
    type_filter: Bool,
    /// When a program state recurs, do not offer the edit chosen there last time.
    no_repeats: Bool,
    /// Keep the selection on the next `?` and only ask what fills it.
    focus_holes: Bool,
    /// The most instances of one compound offered at a time.
    compound_instances: Int,
    /// List the type each hole must have in the state.
    hole_types: Bool,
    /// In hole mode, how many holes Jev is asked to fill in one request.
    cursors: Int,
  )
}

pub fn default_config() {
  Config(
    open_libraries: [],
    compounds: [],
    search_libraries: False,
    advance: True,
    slot_questions: True,
    type_filter: True,
    no_repeats: True,
    focus_holes: False,
    compound_instances: 5,
    hole_types: False,
    cursors: 1,
  )
}

/// The option name shown to Jev and matched against its answer.
pub fn key(option: Option) {
  option.name
}

fn option(action, description) {
  Option(action:, name: a.key(action), description:)
}

fn named(action, name, description) {
  Option(action:, name:, description:)
}

pub fn available(
  buffer: Buffer,
  environment: Environment,
  vocabulary: Vocabulary,
  config: Config,
) -> List(Option) {
  let singles =
    list.flatten([
      structure(buffer, vocabulary, config),
      values(buffer, environment, vocabulary, config),
    ])
  let holes = case buffer.projection, config.focus_holes {
    #(p.Exp(e.Vacant), _), True -> True
    _, _ -> False
  }
  let singles = case holes {
    True -> fills(singles, buffer, environment)
    False -> singles
  }
  let navigation = case holes {
    True ->
      list.filter(navigation(buffer), fn(option) {
        case option.action {
          a.NextVacant | a.JumpToError(_) -> True
          _ -> False
        }
      })
    False -> navigation(buffer)
  }
  // Ordered by priority, builtins are last and dropped first if there are too many.
  // A long task can offer many names, each kind of binding is limited so they
  // do not crowd out values.
  list.flatten([
    navigation,
    [
      option(a.RunTests, "Run the `tests` of the program and see the results."),
      option(a.Finish, "The program is complete and satisfies the task."),
    ],
    compounds(buffer, vocabulary, config, singles),
    prioritise(singles, vocabulary.builtins),
  ])
  |> list.unique
}

fn navigation(buffer: Buffer) {
  let moves = [
    #(a.Next, "Move the cursor to the next node in reading order."),
    #(a.Previous, "Move the cursor to the previous node in reading order."),
    #(a.Up, "Move to the assignment or match branch above."),
    #(a.Down, "Move to the assignment or match branch below."),
    #(a.Parent, "Grow the selection to the enclosing expression."),
    #(a.NextVacant, "Move to the next `?` that still needs writing."),
  ]
  let errors =
    list.index_map(a.type_errors(buffer), fn(error, i) {
      let #(_rev, reason) = error
      #(
        a.JumpToError(i),
        "Select the code with the error: " <> describe_error(reason),
      )
    })
  list.append(moves, errors)
  |> list.filter_map(fn(move) {
    let #(action, description) = move
    case navigable(action, buffer) {
      True -> Ok(option(action, description))
      False -> Error(Nil)
    }
  })
}

fn navigable(action, buffer: Buffer) {
  // Jumping and moving are only useful if the selection changes.
  result.is_ok(a.apply(action, buffer, environment.pure()))
}

pub fn describe_error(reason) {
  case reason {
    error.MissingVariable(var) -> "the variable `" <> var <> "` is not defined"
    error.MissingBuiltin(id) -> "there is no builtin `!" <> id <> "`"
    error.MissingReference(_) -> "the reference cannot be found"
    error.TypeMismatch(expected, given) ->
      "expected "
      <> environment.show_type(expected)
      <> " but found "
      <> environment.show_type(given)
    error.MissingRow(label) -> "the field or tag `" <> label <> "` is missing"
    error.Recursive -> "the type is recursive"
    error.SameTail(_, _) -> "the rows have the same tail"
    error.Todo -> "the program is incomplete"
  }
}

/// Names for new variables and parameters, most likely first.
/// `_` comes first as it is always useful, then names not yet written, names
/// reused from elsewhere in the program and last names shadowing a variable in scope.
pub fn names(buffer: Buffer, vocabulary: Vocabulary) -> List(String) {
  let scope =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> list.map(fn(entry) { entry.0 })
  let builtins = list.map(infer.builtins(), fn(builtin) { builtin.0 })
  let names =
    list.filter(vocabulary.names, fn(name) {
      name != "_" && !list.contains(builtins, name)
    })
  let written = vocabulary.from_program(p.rebuild(buffer.projection)).names
  // Scope is most recent first, a recent definition is the most likely to be shadowed.
  let shadowing = list.filter(scope, list.contains(names, _)) |> list.unique
  let names = list.filter(names, fn(n) { !list.contains(scope, n) })
  let #(fresh, reused) =
    list.partition(names, fn(n) { !list.contains(written, n) })
  [
    "_",
    ..list.flatten([
      list.take(fresh, 15),
      list.take(reused, 10),
      list.take(shadowing, 10),
      list.drop(fresh, 15),
      list.drop(reused, 10),
      list.drop(shadowing, 10),
    ])
  ]
}

/// Text an edit needs that is asked for in its own question, rather than
/// offering the edit once for every candidate.
pub type Slot {
  NameSlot
  LabelSlot
  StringSlot
  IntegerSlot
}

pub fn slot_id(slot) {
  case slot {
    NameSlot -> "name"
    LabelSlot -> "label"
    StringSlot -> "string"
    IntegerSlot -> "integer"
  }
}

pub fn slot_instructions(slot) {
  case slot {
    NameSlot ->
      "If the next edit introduces a variable or parameter, or renames one, which name should it have? Choose the name the task needs next."
    LabelSlot ->
      "If the next edit selects, sets or adds a record field, which field label should it use? Choose the label the task needs next."
    StringSlot ->
      "If the next edit writes a string literal, which string should it be? Choose the string the task needs next."
    IntegerSlot ->
      "If the next edit writes an integer literal, which integer should it be? Choose the integer the task needs next."
  }
}

/// The slot an edit is waiting for, the text it needs is empty.
pub fn slot(action) -> Result(Slot, Nil) {
  case action {
    a.Function("") | a.Assign("") | a.AssignBefore("") | a.Rename("") ->
      Ok(NameSlot)
    a.Select("")
    | a.Overwrite("")
    | a.Record([""])
    | a.InsertBefore(Some(""))
    | a.InsertAfter(Some("")) -> Ok(LabelSlot)
    a.ChooseString -> Ok(StringSlot)
    a.ChooseInteger -> Ok(IntegerSlot)
    _ -> Error(Nil)
  }
}

pub fn fill(action, text) {
  case action {
    a.Function("") -> a.Function(text)
    a.Assign("") -> a.Assign(text)
    a.AssignBefore("") -> a.AssignBefore(text)
    a.Rename("") -> a.Rename(text)
    a.Select("") -> a.Select(text)
    a.Overwrite("") -> a.Overwrite(text)
    a.Record([""]) -> a.Record([text])
    a.InsertBefore(Some("")) -> a.InsertBefore(Some(text))
    a.InsertAfter(Some("")) -> a.InsertAfter(Some(text))
    a.ChooseString -> a.String(unquote(text))
    a.ChooseInteger ->
      case int.parse(text) {
        Ok(value) -> a.Integer(value)
        Error(Nil) -> action
      }
    _ -> action
  }
}

/// The action with its text removed and that text, if the text can be asked for separately.
pub fn unfill(action) -> Result(#(Action, String), Nil) {
  case action {
    a.Function(text) -> Ok(#(a.Function(""), text))
    a.Assign(text) -> Ok(#(a.Assign(""), text))
    a.AssignBefore(text) -> Ok(#(a.AssignBefore(""), text))
    a.Rename(text) -> Ok(#(a.Rename(""), text))
    a.Select(text) -> Ok(#(a.Select(""), text))
    a.Overwrite(text) -> Ok(#(a.Overwrite(""), text))
    a.Record([text]) -> Ok(#(a.Record([""]), text))
    a.InsertBefore(Some(text)) -> Ok(#(a.InsertBefore(Some("")), text))
    a.InsertAfter(Some(text)) -> Ok(#(a.InsertAfter(Some("")), text))
    a.String(text) -> Ok(#(a.ChooseString, quote(text)))
    a.Integer(value) -> Ok(#(a.ChooseInteger, int.to_string(value)))
    _ -> Error(Nil)
  }
}

/// The candidates offered in the question for a slot.
pub fn candidates(slot, buffer, vocabulary: Vocabulary) -> List(String) {
  case slot {
    NameSlot -> names(buffer, vocabulary)
    LabelSlot -> vocabulary.labels
    StringSlot -> list.map(vocabulary.strings, quote)
    IntegerSlot -> list.map(vocabulary.integers, int.to_string)
  }
}

pub fn without_name(action) {
  case unfill(action) {
    Ok(#(action, _)) -> action
    Error(Nil) -> action
  }
}

fn structure(buffer: Buffer, vocabulary: Vocabulary, config: Config) {
  // With a name question one option stands for each kind of binding.
  let names = case config.slot_questions {
    True -> [""]
    False -> names(buffer, vocabulary)
  }
  let vacant = case buffer.projection {
    #(p.Exp(e.Vacant), _) -> True
    _ -> False
  }
  list.flatten([
    when(buffer.insert_function(buffer), fn(_) {
      list.map(names, fn(name) {
        option(
          a.Function(name),
          "Replace the selection with a function taking `"
            <> named_by(name)
            <> "`, the selection becomes its body.",
        )
      })
    }),
    when(buffer.call_many(buffer), fn(_) {
      let arity = int.max(buffer.target_arity(buffer) |> result.unwrap(1), 1)
      let holes = list.repeat("?", arity) |> string.join(", ")
      [
        named(
          a.Call,
          "call " <> selected(buffer) <> "(" <> holes <> ")",
          "Call the selection with "
            <> int.to_string(arity)
            <> " argument(s), the cursor moves to the first argument.",
        ),
      ]
    }),
    when(buffer.call_with(buffer), fn(_) {
      [
        named(
          a.CallWith,
          "pass " <> selected(buffer) <> " to ?(..)",
          "Pass the selection as the argument to a function still to be written.",
        ),
      ]
    }),
    when(buffer.assign(buffer), fn(_) {
      list.map(names, fn(name) {
        option(
          a.Assign(name),
          "Assign a new variable `" <> named_by(name) <> "` here.",
        )
      })
    }),
    when(buffer.assign_before(buffer), fn(_) {
      use <- bool.guard(vacant, [])
      list.map(names, fn(name) {
        option(
          a.AssignBefore(name),
          "Assign a new variable `"
            <> named_by(name)
            <> "` above the current line.",
        )
      })
    }),
    inserts(buffer, vocabulary, config),
    when(buffer.spread(buffer), fn(_) {
      [option(a.Spread, "Make the list or match open to more items.")]
    }),
    when(buffer.delete(buffer), fn(_) {
      [option(a.Delete, "Delete the selection.")]
    }),
    when(buffer.undo(buffer), fn(_) { [option(a.Undo, "Undo the last edit.")] }),
    renames(buffer, vocabulary, config),
    destructures(buffer, vocabulary),
  ])
}

// A pattern can destructure the fields of the value assigned, or a pattern the task names.
fn destructures(buffer: Buffer, vocabulary: Vocabulary) {
  let from_type = case buffer.projection {
    #(p.Assign(p.AssignPattern(_), ..), _)
    | #(p.Assign(p.AssignStatement(_), ..), _) -> {
      let path = p.path(buffer.projection)
      let value = case list.reverse(path) {
        [0, ..rest] -> list.reverse([1, ..rest])
        _ -> list.append(path, [1])
      }
      case infer.type_at(buffer.analysis, list.reverse(value)) {
        Ok(t.Record(rows)) -> [
          list.map(analysis.rows(rows), fn(field) { #(field.0, field.0) }),
        ]
        _ -> []
      }
    }
    _ -> []
  }
  case buffer.projection {
    #(p.Assign(p.AssignPattern(_), ..), _)
    | #(p.Assign(p.AssignStatement(_), ..), _)
    | #(p.FnParam(p.AssignPattern(_), ..), _) ->
      list.append(from_type, vocabulary.patterns)
      |> list.unique
      |> list.map(fn(fields) {
        option(a.Destructure(fields), "Destructure the value into its fields.")
      })
    _ -> []
  }
}

fn inserts(buffer, vocabulary: Vocabulary, config: Config) {
  let labels = case config.slot_questions {
    True -> [""]
    False -> vocabulary.labels
  }
  let describe = fn(position) {
    "Add another element " <> position <> " the selection."
  }
  let labelled = fn(label, position) {
    "Add `" <> label <> "` " <> position <> " the selection."
  }
  let options = fn(continue, action, position) {
    case continue {
      Ok(buffer.Done(_)) -> [option(action(None), describe(position))]
      Ok(buffer.WithString(_)) ->
        list.map(labels, fn(label) {
          option(action(Some(label)), labelled(label, position))
        })
      Error(Nil) -> []
    }
  }
  list.append(
    options(buffer.insert_before(buffer), a.InsertBefore, "before"),
    options(buffer.insert_after(buffer), a.InsertAfter, "after"),
  )
}

fn values(
  buffer: Buffer,
  environment: Environment,
  vocabulary,
  config: Config,
) {
  case buffer.projection {
    #(p.Exp(e.Vacant), _) if config.type_filter -> {
      let expected = buffer.target_type(buffer)
      let scope = buffer.target_scope(buffer) |> result.unwrap([])
      expression_values(buffer, environment, vocabulary, config)
      |> list.filter(fn(option) {
        case value_type(option.action, scope, environment) {
          Ok(type_) -> fits(expected, type_)
          Error(Nil) -> True
        }
      })
    }
    #(p.Exp(_), _) -> expression_values(buffer, environment, vocabulary, config)
    _ -> []
  }
}

// The type of the value an option would write, if it writes one.
fn value_type(action, scope, environment: Environment) {
  case action {
    a.Variable(name) -> list.key_find(scope, name) |> result.map(instantiate)
    a.Builtin(name) ->
      list.key_find(infer.builtins(), name) |> result.map(instantiate)
    a.String(_) | a.ChooseString -> Ok(t.String)
    a.Integer(_) | a.ChooseInteger -> Ok(t.Integer)
    a.EmptyList -> Ok(t.List(t.Var(0)))
    a.EmptyRecord | a.Record(_) -> Ok(t.Record(t.Empty))
    a.Tag(_) -> Ok(t.Fun(t.Var(0), t.Empty, t.Union(t.Var(1))))
    a.Reference(ir.Pinned(release)) ->
      environment.library_by_module(environment, release.module)
      |> result.map(fn(library) { instantiate(library.type_) })
    _ -> Error(Nil)
  }
}

// A value fits a hole when their types start the same, when calling it or
// selecting one of its fields gives a value that fits, or when it can be matched on.
fn fits(expected, candidate) {
  do_fits(expected, candidate, 2)
}

fn do_fits(expected, candidate, depth) {
  case expected, candidate {
    Error(Nil), _ | Ok(t.Var(_)), _ | _, t.Var(_) -> True
    Ok(t.Integer), t.Integer
    | Ok(t.String), t.String
    | Ok(t.Binary), t.Binary
    | Ok(t.List(_)), t.List(_)
    | Ok(t.Record(_)), t.Record(_)
    | Ok(t.Union(_)), t.Union(_)
    | Ok(t.Fun(..)), t.Fun(..)
    -> True
    // A union can be matched on to give a value of any type.
    Ok(_), t.Union(_) -> True
    Ok(_), t.Fun(_, _, return) -> do_fits(expected, return, depth)
    Ok(_), t.Record(rows) if depth > 0 ->
      list.any(analysis.rows(rows), fn(field) {
        do_fits(expected, field.1, depth - 1)
      })
    _, _ -> False
  }
}

fn expression_values(
  buffer: Buffer,
  environment: Environment,
  vocabulary: Vocabulary,
  config: Config,
) {
  let scope =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> list.filter(fn(entry) { entry.0 != "_" && entry.0 != "$" })
    |> list.unique
  // Choosing the selected variable again keeps it, see `action.perform`.
  let selected = case buffer.projection {
    #(p.Exp(e.Variable(name)), _) -> name
    _ -> "_"
  }
  let fields = buffer.fields(buffer)
  let variants = buffer.varients(buffer)
  // Known fields are offered directly, otherwise the label is asked for separately.
  let labels = case fields, config.slot_questions {
    [], True -> [""]
    [], False -> vocabulary.labels
    _, _ -> list.map(fields, fn(field) { field.0 })
  }
  let tags =
    list.map(variants, fn(variant) { variant.0 })
    |> list.append(vocabulary.tags)
    |> list.unique
  let effects = environment.effect_signatures(environment)
  list.flatten([
    list.map(scope, fn(entry) {
      let #(name, poly) = entry
      let description = case name == selected {
        True -> "Keep this variable and move on to the next hole."
        False -> "A variable of type " <> environment.render_poly(poly)
      }
      option(a.Variable(name), description)
    }),
    // A few literals are offered directly, many are chosen by their own question.
    case
      config.slot_questions
      && list.length(vocabulary.strings) > literals_offered
    {
      True -> [
        option(
          a.ChooseString,
          "A string literal chosen by the string question.",
        ),
      ]
      False ->
        list.map(vocabulary.strings, fn(value) {
          option(a.String(value), "A string literal.")
        })
    },
    case
      config.slot_questions
      && list.length(vocabulary.integers) > literals_offered
    {
      True -> [
        option(
          a.ChooseInteger,
          "An integer literal chosen by the integer question.",
        ),
      ]
      False ->
        list.map(vocabulary.integers, fn(value) {
          option(a.Integer(value), "An integer literal.")
        })
    },
    list.map(tags, fn(label) {
      option(
        a.Tag(label),
        "The tag `" <> label <> "`, call it to wrap a value.",
      )
    }),
    [
      option(a.EmptyList, "An empty list."),
      option(a.List, "Wrap the selection as the first item in a list."),
      option(a.EmptyRecord, "An empty record."),
    ],
    case fields {
      [] ->
        list.append(
          list.map(vocabulary.records, fn(labels) {
            option(a.Record(labels), "A record with these fields.")
          }),
          list.map(labels, fn(label) {
            option(
              a.Record([label]),
              "A record with the field `" <> label <> "`.",
            )
          }),
        )
      _ -> [option(a.Record(labels), "A record with the expected fields.")]
    },
    list.map(labels, fn(label) {
      let type_ = case list.key_find(fields, label) {
        Ok(type_) -> " of type " <> environment.show_type(type_)
        Error(Nil) -> ""
      }
      option(
        a.Select(label),
        "Select the field `" <> label <> "`" <> type_ <> " from the selection.",
      )
    }),
    list.map(labels, fn(label) {
      option(
        a.Overwrite(label),
        "Copy the selected record with a new value for `" <> label <> "`.",
      )
    }),
    case variants {
      [] ->
        list.append(
          list.map(vocabulary.unions, fn(labels) {
            option(
              a.Match(labels),
              "Match on the selection with these branches.",
            )
          }),
          list.map(vocabulary.tags, fn(label) {
            option(
              a.Match([label]),
              "Match on the selection, starting with the `"
                <> label
                <> "` branch.",
            )
          }),
        )
      _ -> [
        option(
          a.Match(list.map(variants, fn(v) { v.0 })),
          "Match on every variant of the selection.",
        ),
        ..list.append(
          list.filter_map(vocabulary.unions, fn(labels) {
            let known = list.map(variants, fn(v) { v.0 })
            case list.all(labels, list.contains(known, _)) {
              True ->
                Ok(option(
                  a.Match(labels),
                  "Match on the selection with these branches.",
                ))
              False -> Error(Nil)
            }
          }),
          list.map(variants, fn(variant) {
            option(
              a.Match([variant.0]),
              "Match the `"
                <> variant.0
                <> "` variant, other variants can go to an otherwise branch.",
            )
          }),
        )
      ]
    },
    list.map(effects, fn(effect) {
      let #(label, signature) = effect
      option(a.Perform(label), "Perform the effect: " <> signature)
    }),
    list.map(effects, fn(effect) {
      let #(label, signature) = effect
      option(a.Handle(label), "Handle the effect in a function, " <> signature)
    }),
    list.filter_map(config.open_libraries, fn(name) {
      use library <- result.map(environment.find_library(environment, name))
      option(
        a.Reference(ir.Pinned(library.release)),
        "The library @" <> library.name <> ".",
      )
    }),
    case config.search_libraries {
      True ->
        list.filter_map(environment.libraries, fn(library) {
          let open = list.contains(config.open_libraries, library.name)
          // Modules named by content id are only imported by other libraries.
          let released = !string.starts_with(library.name, "#")
          case !open && released {
            False -> Error(Nil)
            True ->
              Ok(option(
                a.OpenLibrary(library.name),
                "Read the API of the library @"
                  <> library.name
                  <> summary(library.readme),
              ))
          }
        })
      False -> []
    },
    list.map(infer.builtins(), fn(builtin) {
      let #(name, poly) = builtin
      option(
        a.Builtin(name),
        "A builtin of type " <> environment.render_poly(poly),
      )
    }),
  ])
}

// Fill the slots of each compound from the context: recent variables, the
// fields of the value selected from, and builtins and tags the task mentions.
// An instance is offered if its first step is, later steps are checked when applied.
fn compounds(buffer: Buffer, vocabulary: Vocabulary, config: Config, singles) {
  let offered = list.map(singles, fn(option: Option) { option.action })
  let context = slot_context(buffer, vocabulary)
  list.flat_map(config.compounds, fn(template) {
    instantiate_steps(template, context, None)
    |> list.filter(fn(steps) {
      case steps {
        [first, ..] ->
          list.contains(offered, first)
          || list.contains(offered, without_name(first))
          || a.is_navigation(first)
        [] -> False
      }
    })
    |> list.take(config.compound_instances)
    |> list.map(fn(steps) {
      let name = string.join(list.map(steps, a.key), ", ")
      named(
        a.Compound(name, steps),
        name,
        "Several edits in one: " <> string.join(list.map(steps, a.key), ", "),
      )
    })
  })
}

type SlotContext {
  SlotContext(
    variables: List(#(String, t.Type(Int))),
    builtins: List(#(String, t.Type(Int))),
    tags: List(String),
    strings: List(String),
    integers: List(Int),
    names: List(String),
  )
}

fn slot_context(buffer: Buffer, vocabulary: Vocabulary) {
  let variables =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> list.filter(fn(entry) { entry.0 != "_" && entry.0 != "$" })
    |> list.unique
    |> list.map(fn(entry) { #(entry.0, instantiate(entry.1)) })
    |> list.take(6)
  let used = text.print(p.rebuild(buffer.projection))
  let builtins =
    infer.builtins()
    |> list.filter(fn(builtin) {
      string.contains(used, "!" <> builtin.0)
      || list.contains(vocabulary.names, builtin.0)
    })
    |> list.map(fn(entry) { #(entry.0, instantiate(entry.1)) })
    |> list.take(4)
  SlotContext(
    variables:,
    builtins:,
    tags: list.take(vocabulary.tags, 4),
    strings: list.take(vocabulary.strings, 4),
    integers: list.take(vocabulary.integers, 3),
    names: list.take(vocabulary.names, 4),
  )
}

fn instantiate(poly) {
  let #(type_, _) = binding.instantiate(poly, 0, dict.new())
  type_
}

// `value` is the type of the expression built so far, used for selecting fields.
fn instantiate_steps(steps, context: SlotContext, value) -> List(List(Action)) {
  case steps {
    [] -> [[]]
    [step, ..rest] -> {
      let choices = case step, value {
        a.Variable(""), _ ->
          list.map(context.variables, fn(v) { #(a.Variable(v.0), Some(v.1)) })
        a.Select(""), Some(t.Record(rows)) ->
          analysis.rows(rows)
          |> list.take(8)
          |> list.map(fn(field) { #(a.Select(field.0), Some(field.1)) })
        a.Select(""), _ -> []
        a.Builtin(""), _ ->
          list.map(context.builtins, fn(b) { #(a.Builtin(b.0), Some(b.1)) })
        a.Tag(""), _ -> list.map(context.tags, fn(l) { #(a.Tag(l), None) })
        a.String(""), _ ->
          list.map(context.strings, fn(s) { #(a.String(s), None) })
        a.Integer(0), _ ->
          list.map(context.integers, fn(n) { #(a.Integer(n), None) })
        a.Function(""), _ ->
          list.map(context.names, fn(n) { #(a.Function(n), None) })
        a.Assign(""), _ ->
          list.map(context.names, fn(n) { #(a.Assign(n), None) })
        a.Call, Some(t.Fun(_, _, return)) -> [#(a.Call, Some(return))]
        _, _ -> [#(step, None)]
      }
      list.flat_map(choices, fn(choice) {
        let #(step, value) = choice
        instantiate_steps(rest, context, value)
        |> list.map(fn(steps) { [step, ..steps] })
      })
    }
  }
}

fn when(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(_) -> []
  }
}

/// A short description of what is selected, for example `vacant expression`.
pub fn focus_kind(buffer: Buffer) -> String {
  case buffer.projection {
    #(p.Exp(e.Vacant), _) -> "an empty expression `?`"
    #(p.Exp(_), _) -> "an expression"
    #(p.Assign(p.AssignStatement(_), ..), _) -> "an assignment"
    #(p.Assign(..), _) -> "an assignment pattern"
    #(p.FnParam(..), _) -> "a function parameter"
    #(p.Label(..), _) -> "a record field label"
    #(p.Select(..), _) -> "a selected field label"
    #(p.Match(..), _) -> "a match branch label"
  }
}

// The selected expression as short text for option names.
fn selected(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(exp), _) -> {
      let code = text.print(exp) |> string.replace("\n", " ")
      case string.length(code) > 40 {
        True -> string.slice(code, 0, 37) <> "..."
        False -> code
      }
    }
    _ -> "selection"
  }
}

// Patterns and labels can be renamed, expressions are replaced instead.
fn renames(buffer: Buffer, vocabulary: Vocabulary, config: Config) {
  let candidates = case buffer.projection {
    #(p.Assign(..), _) | #(p.FnParam(..), _) if config.slot_questions -> [""]
    #(p.Assign(..), _) | #(p.FnParam(..), _) -> vocabulary.names
    #(p.Label(..), _) | #(p.Select(..), _) -> vocabulary.labels
    #(p.Match(..), _) -> vocabulary.tags
    #(p.Exp(_), _) -> []
  }
  case buffer.insert(buffer) {
    Ok(#(current, _)) ->
      list.filter(candidates, fn(name) { name != current })
      |> list.map(fn(name) {
        option(
          a.Rename(name),
          "Rename the selection to `" <> named_by(name) <> "`.",
        )
      })
    Error(Nil) -> []
  }
}

// Each kind of option with its priority and the most offered, names and literals from
// a long task would otherwise crowd out everything else.
fn rank(action) -> #(Int, Int) {
  case action {
    a.Variable(_) -> #(1, 30)
    a.Function(_) -> #(2, 40)
    a.Assign(_) | a.AssignBefore(_) -> #(2, 40)
    a.String(_) -> #(3, 25)
    a.Integer(_) -> #(3, 25)
    a.Tag(_) -> #(4, 20)
    a.Record(_) -> #(4, 15)
    a.Match(_) -> #(4, 12)
    a.Select(_) -> #(5, 20)
    a.Overwrite(_) -> #(5, 10)
    a.Reference(_) | a.OpenLibrary(_) -> #(6, 20)
    a.Destructure(_) -> #(7, 20)
    a.Rename(_) -> #(7, 40)
    a.InsertBefore(Some(_)) | a.InsertAfter(Some(_)) -> #(7, 12)
    a.Perform(_) | a.Handle(_) -> #(8, 40)
    a.Builtin(_) -> #(9, 60)
    _ -> #(0, 20)
  }
}

fn prioritise(options: List(Option), mentioned) {
  let #(kept, _) =
    list.fold(options, #([], dict.new()), fn(acc, option) {
      let #(kept, counts) = acc
      let #(priority, most) = case option.action {
        a.Builtin(name) ->
          case list.contains(mentioned, name) {
            True -> #(3, 30)
            False -> rank(option.action)
          }
        _ -> rank(option.action)
      }
      let key = case priority, option.action {
        3, a.Builtin(_) -> "mentioned builtin"
        _, _ -> kind_name(option.action)
      }
      let seen = dict.get(counts, key) |> result.unwrap(0)
      case seen < most {
        True -> #(
          [#(priority, option), ..kept],
          dict.insert(counts, key, seen + 1),
        )
        False -> acc
      }
    })
  list.reverse(kept)
  |> list.sort(fn(x, y) { int.compare(x.0, y.0) })
  |> list.map(fn(entry) { entry.1 })
}

// Options are counted by the first word of their key, `let x =` and `let x = above` together.
fn kind_name(action) {
  case string.split(a.key(action), " ") {
    [first, ..] -> first
    [] -> ""
  }
}

// An empty name is filled from the answer to the name question.
fn named_by(name) {
  case name {
    "" -> "?`, named by the answer to the name question, `"
    _ -> name
  }
}

const literals_offered = 12

fn quote(text) {
  "\""
  <> string.replace(text, "\\", "\\\\") |> string.replace("\"", "\\\"")
  <> "\""
}

fn unquote(text) {
  case string.starts_with(text, "\"") && string.ends_with(text, "\"") {
    True ->
      text
      |> string.drop_start(1)
      |> string.drop_end(1)
      |> string.replace("\\\"", "\"")
      |> string.replace("\\\\", "\\")
    False -> text
  }
}

// The first paragraph of a readme after its title.
fn summary(readme) {
  let paragraph =
    string.split(readme, "\n\n")
    |> list.find(fn(p) { p != "" && !string.starts_with(p, "#") })
  case paragraph {
    Ok(paragraph) -> ": " <> string.replace(paragraph, "\n", " ")
    Error(Nil) -> "."
  }
}

// With the selection kept on holes a function is offered called, `call f(?, ?)`,
// as the selection moves on straight away and could not be called afterwards.
// It is also offered uncalled where the hole takes a function.
fn fills(singles: List(Option), buffer: Buffer, environment: Environment) {
  let expected = buffer.target_type(buffer)
  let scope = buffer.target_scope(buffer) |> result.unwrap([])
  // A hole of unknown type rarely wants a function that is not called.
  let takes_function = case expected {
    Ok(t.Fun(..)) -> True
    _ -> False
  }
  list.flat_map(singles, fn(option) {
    case option.action {
      a.Variable(_) | a.Builtin(_) | a.Tag(_) ->
        case value_type(option.action, scope, environment) {
          Ok(t.Fun(..) as type_) -> {
            let holes = list.repeat("?", arity(type_)) |> string.join(", ")
            let name = case option.action {
              a.Variable(name) -> name
              a.Builtin(name) -> "!" <> name
              a.Tag(label) -> label
              _ -> ""
            }
            let key = "call " <> name <> "(" <> holes <> ")"
            let called =
              named(
                a.Compound(key, [option.action, a.Call]),
                key,
                option.description
                  <> ", called with the cursor on its first argument.",
              )
            case takes_function {
              True -> [called, option]
              False -> [called]
            }
          }
          _ -> [option]
        }
      _ -> [option]
    }
  })
}

fn arity(type_) {
  case type_ {
    t.Fun(_, _, return) -> 1 + arity(return)
    _ -> 0
  }
}
