//// The actions available at the current focus, each with a description for Jev.
//// Availability is checked once per kind of action without applying it,
//// so offering many names does not require reanalysing the program for each.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/ir/tree as ir
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import jev_playground/action.{type Action} as a
import jev_playground/environment.{type Environment}
import jev_playground/vocabulary.{type Vocabulary}
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
    /// Named sequences of actions offered alongside single edits.
    compounds: List(Action),
    /// Offer to open libraries that are not yet open.
    search_libraries: Bool,
    /// Move to the next `?` after filling one with a complete value.
    advance: Bool,
  )
}

pub fn default_config() {
  Config(
    open_libraries: [],
    compounds: [],
    search_libraries: False,
    advance: True,
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
  // Ordered by priority, builtins are last and dropped first if there are too many.
  list.flatten([
    navigation(buffer),
    [
      option(a.RunTests, "Run the `tests` of the program and see the results."),
      option(a.Finish, "The program is complete and satisfies the task."),
    ],
    compounds(buffer, environment, config),
    structure(buffer, vocabulary),
    values(buffer, environment, vocabulary, config),
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
  case action {
    a.JumpToError(_) -> True
    _ -> result.is_ok(a.apply(action, buffer, environment.pure()))
  }
}

pub fn describe_error(reason) {
  case reason {
    error.MissingVariable(var) -> "the variable `" <> var <> "` is not defined"
    error.MissingBuiltin(id) -> "there is no builtin `!" <> id <> "`"
    error.MissingReference(_) -> "the reference cannot be found"
    error.TypeMismatch(expected, given) ->
      "expected " <> debug.mono(expected) <> " but found " <> debug.mono(given)
    error.MissingRow(label) -> "the field or tag `" <> label <> "` is missing"
    error.Recursive -> "the type is recursive"
    error.SameTail(_, _) -> "the rows have the same tail"
    error.Todo -> "the program is incomplete"
  }
}

fn structure(buffer: Buffer, vocabulary: Vocabulary) {
  // New bindings do not shadow variables in scope or reuse builtin names.
  let scope =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> list.map(fn(entry) { entry.0 })
  let builtins = list.map(infer.builtins(), fn(builtin) { builtin.0 })
  let names =
    list.filter(vocabulary.names, fn(name) {
      name == "_"
      || { !list.contains(scope, name) && !list.contains(builtins, name) }
    })
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
            <> name
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
        option(a.Assign(name), "Assign a new variable `" <> name <> "` here.")
      })
    }),
    when(buffer.assign_before(buffer), fn(_) {
      use <- bool.guard(vacant, [])
      list.map(names, fn(name) {
        option(
          a.AssignBefore(name),
          "Assign a new variable `" <> name <> "` above the current line.",
        )
      })
    }),
    inserts(buffer, vocabulary),
    when(buffer.spread(buffer), fn(_) {
      [option(a.Spread, "Make the list or match open to more items.")]
    }),
    when(buffer.delete(buffer), fn(_) {
      [option(a.Delete, "Delete the selection.")]
    }),
    when(buffer.undo(buffer), fn(_) { [option(a.Undo, "Undo the last edit.")] }),
    renames(buffer, vocabulary),
  ])
}

fn inserts(buffer, vocabulary: Vocabulary) {
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
        list.map(vocabulary.labels, fn(label) {
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
    #(p.Exp(_), _) -> expression_values(buffer, environment, vocabulary, config)
    _ -> []
  }
}

fn expression_values(
  buffer,
  environment: Environment,
  vocabulary: Vocabulary,
  config: Config,
) {
  let scope =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> list.filter(fn(entry) { entry.0 != "_" && entry.0 != "$" })
    |> list.unique
  let fields = buffer.fields(buffer)
  let variants = buffer.varients(buffer)
  let labels = case fields {
    [] -> vocabulary.labels
    _ -> list.map(fields, fn(field) { field.0 })
  }
  let tags =
    list.map(variants, fn(variant) { variant.0 })
    |> list.append(vocabulary.tags)
    |> list.unique
  let effects = environment.effect_signatures(environment)
  list.flatten([
    list.map(scope, fn(entry) {
      let #(name, poly) = entry
      option(
        a.Variable(name),
        "A variable of type " <> environment.render_poly(poly),
      )
    }),
    list.map(vocabulary.strings, fn(value) {
      option(a.String(value), "A string literal.")
    }),
    list.map(vocabulary.integers, fn(value) {
      option(a.Integer(value), "An integer literal.")
    }),
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
        Ok(type_) -> " of type " <> debug.mono(type_)
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
        list.map(vocabulary.tags, fn(label) {
          option(
            a.Match([label]),
            "Match on the selection, starting with the `"
              <> label
              <> "` branch.",
          )
        })
      _ -> [
        option(
          a.Match(list.map(variants, fn(v) { v.0 })),
          "Match on every variant of the selection.",
        ),
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
          case list.contains(config.open_libraries, library.name) {
            True -> Error(Nil)
            False ->
              Ok(option(
                a.OpenLibrary(library.name),
                "Read the API of the library @" <> library.name <> ".",
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

fn compounds(buffer, environment, config: Config) {
  list.filter_map(config.compounds, fn(compound) {
    case a.perform(compound, buffer, environment, config.advance) {
      Ok(_) -> Ok(option(compound, compound_description(compound)))
      Error(Nil) -> Error(Nil)
    }
  })
}

fn compound_description(compound) {
  case compound {
    a.Compound(steps:, ..) ->
      "Several edits in one: " <> string.join(list.map(steps, a.key), ", ")
    _ -> ""
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
fn renames(buffer: Buffer, vocabulary: Vocabulary) {
  let candidates = case buffer.projection {
    #(p.Assign(..), _) | #(p.FnParam(..), _) -> vocabulary.names
    #(p.Label(..), _) | #(p.Select(..), _) -> vocabulary.labels
    #(p.Match(..), _) -> vocabulary.tags
    #(p.Exp(_), _) -> []
  }
  case buffer.insert(buffer) {
    Ok(#(current, _)) ->
      list.filter(candidates, fn(name) { name != current })
      |> list.map(fn(name) {
        option(a.Rename(name), "Rename the selection to `" <> name <> "`.")
      })
    Error(Nil) -> []
  }
}
