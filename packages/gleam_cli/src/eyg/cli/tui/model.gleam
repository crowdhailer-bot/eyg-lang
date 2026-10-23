//// What the tui shows, and how keys and the shell change it. Nothing here
//// performs effects: changes that need the outside world are commands for the
//// tui loop.

import eyg/analysis/type_/binding
import eyg/cli/tui/completion.{type Completion}
import eyg/cli/tui/editor.{type Editor}
import eyg/cli/tui/shell
import eyg/cli/tui/structural
import eyg/ir/tree
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import loam/source
import morph/buffer
import morph/manipulation as m

pub type Entry {
  Entry(
    id: Int,
    source: String,
    output: String,
    results: List(Result(String, String)),
    performed: List(shell.Performed),
    fetches: List(String),
    duration: Option(Float),
    expanded: Bool,
    busy: Bool,
    structural: Bool,
  )
}

/// An expression edited structurally, with the earlier expressions that were
/// evaluated and the text it was made from.
pub type Structure {
  Structure(
    buffer: buffer.Buffer,
    input: Option(Input),
    previous: List(buffer.Buffer),
    after: Option(buffer.Buffer),
    imported: String,
  )
}

/// A value a structural edit needs, answered in the editor.
pub type Input {
  Input(input: m.UserInput, label: String, kind: Kind)
}

pub type Kind {
  TextInput
  FileInput
  PackageInput
}

pub type Model {
  Model(
    shell: Option(shell.Shell),
    busy: Bool,
    entries: List(Entry),
    editor: Editor,
    prompt: Option(#(String, Editor)),
    status: String,
    help: Bool,
    sequence: Int,
    directory: String,
    packages: List(String),
    choices: List(Completion),
    choice: Int,
    structural: Bool,
    structure: Option(Structure),
    references: List(#(tree.Reference, binding.Poly)),
    loading: List(tree.Reference),
    clipboard: String,
  )
}

/// Something a click on the screen does.
pub type Click {
  ToggleEffects(Int)
  Focus(List(Int))
}

pub type Code {
  Text(String)
  Ir(tree.Node(source.Location))
}

pub type Command {
  Evaluate(id: Int, code: Code)
  Answer(String)
  Quit
  FollowTail
  Reveal(String)
  Scroll(Int)
  /// Find completions for the text being written.
  Complete
  /// Copy text to the system clipboard.
  Copy(String)
  /// Find the type of a referenced module.
  Load(tree.Reference)
}

pub fn new(directory) {
  Model(
    shell: None,
    busy: True,
    entries: [],
    editor: editor.new(),
    prompt: None,
    status: "Starting EYG…",
    help: False,
    sequence: 0,
    directory:,
    packages: [],
    choices: [],
    choice: 0,
    structural: False,
    structure: None,
    references: [],
    loading: [],
    clipboard: "",
  )
}

/// The input a structural edit is waiting for.
pub fn input(model: Model) {
  case model.structural, model.structure {
    True, Some(Structure(input: Some(input), ..)) -> Some(input)
    _, _ -> None
  }
}

/// Whether keys go to the text editor.
pub fn editing_text(model: Model) {
  !model.structural || model.prompt != None || input(model) != None
}

pub fn key(model: Model, key: String) -> #(Model, List(Command)) {
  case key, model.choices {
    "ctrl+c", _ -> #(model, [Quit])
    "f1", _ -> #(Model(..model, help: !model.help), [])
    "f2", _ -> switch(model)
    "ctrl+e", _ ->
      case list.find(list.reverse(model.entries), has_effects) {
        Ok(entry) -> click(model, ToggleEffects(entry.id))
        Error(Nil) -> #(model, [])
      }
    "pageup", _ -> #(model, [Scroll(-12)])
    "pagedown", _ -> #(model, [Scroll(12)])
    "tab", [_, ..] -> accept(model)
    "up", [_, ..] -> #(choose(model, -1), [])
    "down", [_, ..] -> #(choose(model, 1), [])
    "esc", [_, ..] -> #(Model(..model, choices: []), [])
    _, _ ->
      case model.prompt, model.structural, model.structure {
        None, True, Some(Structure(input: Some(_), ..) as structure) ->
          case key {
            "esc" -> restructure(model, Structure(..structure, input: None))
            _ -> write(model, key)
          }
        None, True, Some(structure) -> structure_key(model, structure, key)
        _, _, _ -> write(model, key)
      }
  }
}

fn write(model: Model, key) {
  case editor.key(model.editor, key) {
    editor.Edited(editor) -> edited(model, editor)
    editor.Submitted -> submit(model)
    editor.Ignored -> #(model, [])
  }
}

/// Pasted text is typed, or in a structure replaces the selected expression.
pub fn paste(model: Model, text) {
  case model.prompt, model.structural, model.structure, model.shell {
    None, True, Some(Structure(input: None, ..) as structure), Some(shell) ->
      structural.paste(structure.buffer, text, shell.scope, shell.execution)
      |> changed(model, structure, _)
    _, _, _, _ -> edited(model, editor.insert(model.editor, text))
  }
}

fn edited(model: Model, editor: Editor) {
  case model.prompt {
    None -> #(Model(..model, editor:), [Complete])
    Some(_) -> #(Model(..model, editor:), [])
  }
}

fn choose(model: Model, delta) {
  let count = list.length(model.choices)
  Model(..model, choice: { model.choice + delta + count } % count)
}

fn accept(model: Model) {
  case list.drop(model.choices, model.choice) {
    [] -> #(model, [])
    [choice, ..] -> {
      let #(text, prefix) = completion.apply(model.editor.text, choice)
      let editor = editor.Editor(text, string.length(prefix), False)
      #(Model(..model, editor:, choices: []), [])
    }
  }
}

/// Completions found for the text being written.
pub fn completed_choices(model: Model, choices) {
  Model(..model, choices:, choice: 0)
}

/// The published package ledger, pulled in the background, to complete and
/// choose packages.
pub fn discovered(model: Model, execution) {
  case model.shell {
    Some(current) -> {
      let current = shell.with_ledger(current, execution)
      #(
        Model(..model, shell: Some(current), packages: shell.packages(current)),
        [Complete],
      )
    }
    None -> #(model, [])
  }
}

pub fn click(model: Model, click: Click) -> #(Model, List(Command)) {
  case click {
    ToggleEffects(id) -> {
      let model =
        change(model, id, fn(entry) {
          Entry(..entry, expanded: !entry.expanded)
        })
      let anchor = case find(model, id) {
        Ok(Entry(expanded: True, ..)) -> "details-"
        _ -> "effects-"
      }
      #(model, [Reveal(anchor <> int.to_string(id))])
    }
    Focus(path) ->
      case model.structure {
        Some(structure) ->
          buffer.focus_at(structure.buffer, path)
          |> result.unwrap(structure.buffer)
          |> fn(buffer) { restructure(model, Structure(..structure, buffer:)) }
        None -> #(model, [])
      }
  }
}

fn submit(model: Model) {
  let source = model.editor.text
  case model.prompt, input(model), model.structure {
    Some(#(_, draft)), _, _ -> #(
      Model(..model, prompt: None, editor: draft, status: "Running…"),
      [Answer(source)],
    )
    None, Some(Input(input:, ..)), Some(structure) ->
      case model.shell {
        Some(shell) ->
          structural.answer(input, source, shell.scope, shell.execution)
          |> changed(model, structure, _)
        None -> #(model, [])
      }
    _, _, _ ->
      case string.trim(source) {
        "" -> #(model, [])
        "/exit" -> #(model, [Quit])
        _ if model.busy -> #(model, [])
        _ -> run(Model(..model, editor: editor.new()), source, Text(source))
      }
  }
}

/// Start an evaluation, shown in the history as `source`.
fn run(model: Model, source, code) {
  case model.shell, model.busy {
    Some(_), False -> {
      let id = model.sequence + 1
      let entry =
        Entry(
          id:,
          source:,
          output: "",
          results: [],
          performed: [],
          fetches: [],
          duration: None,
          expanded: False,
          busy: True,
          structural: case code {
            Text(_) -> False
            Ir(_) -> True
          },
        )
      #(
        Model(
          ..model,
          busy: True,
          entries: list.append(model.entries, [entry]),
          choices: [],
          sequence: id,
          status: "Running…",
        ),
        [FollowTail, Evaluate(id, code)],
      )
    }
    _, _ -> #(model, [])
  }
}

// Structural editing

/// F2 moves between text and structure. Text that was not changed since it
/// became a structure returns to that structure.
fn switch(model: Model) {
  case model.busy || model.prompt != None, model.structural, model.shell {
    True, _, _ | _, _, None -> #(model, [])
    False, True, _ -> {
      let imported = case model.structure {
        Some(structure) -> structure.imported
        None -> ""
      }
      let editor = editor.from(imported, False)
      #(Model(..model, structural: False, editor:, choices: []), [])
    }
    False, False, Some(shell) -> {
      let text = model.editor.text
      case model.structure {
        Some(structure) if structure.imported == text -> #(
          Model(..model, structural: True, editor: editor.new(), choices: []),
          [],
        )
        _ ->
          case structural.parse(text, shell.scope, shell.execution) {
            Error(message) -> #(Model(..model, status: message), [])
            Ok(buffer) -> {
              let previous = case model.structure {
                Some(structure) -> structure.previous
                None -> []
              }
              let structure = Structure(buffer, None, previous, None, text)
              Model(
                ..model,
                structural: True,
                editor: editor.new(),
                choices: [],
              )
              |> restructure(structure)
            }
          }
      }
    }
  }
}

fn structure_key(model: Model, structure: Structure, key) {
  let buffer = structure.buffer
  case model.busy, key, model.shell {
    True, _, _ | _, _, None -> #(model, [])
    _, "esc", _ -> switch(model)
    _, "enter", _ -> {
      let source = projection_text(structure)
      run(model, source, Ir(structural.executable(buffer)))
    }
    _, "y", _ ->
      case buffer.copy_source(buffer) {
        Ok(text) -> #(
          Model(..model, clipboard: text, status: "Copied expression"),
          [Copy(text)],
        )
        Error(_) -> #(
          Model(..model, status: "Select an expression to copy"),
          [],
        )
      }
    _, "Y", _ ->
      case model.clipboard {
        "" -> #(Model(..model, status: "Nothing has been copied"), [])
        text -> paste(model, text)
      }
    _, "up", _ if structure.previous != [] && structure.after == None -> {
      let assert [last, ..] = structure.previous
      restructure(
        model,
        Structure(..structure, buffer: last, after: Some(buffer)),
      )
    }
    _, "down", _ if structure.after != None -> {
      let assert Some(after) = structure.after
      restructure(model, Structure(..structure, buffer: after, after: None))
    }
    _, _, Some(shell) ->
      case structural.navigate(buffer, key) {
        Ok(buffer) -> restructure(model, Structure(..structure, buffer:))
        Error(_) ->
          case structural.operation(buffer, key, shell.execution) {
            Error(_) -> #(
              Model(..model, status: "Cannot apply " <> key <> " here"),
              [],
            )
            Ok(#(_, m.Resolved(rebuild))) ->
              structural.resolve(rebuild, shell.scope, shell.execution)
              |> Ok
              |> changed(model, structure, _)
            Ok(#(label, m.UserInput(input))) -> {
              let kind = case key {
                "q" | "Q" -> FileInput
                "@" -> PackageInput
                _ -> TextInput
              }
              let #(value, _) = structural.input_details(input)
              let editor = editor.from(value, kind == TextInput)
              let structure =
                Structure(..structure, input: Some(Input(input, label, kind)))
              let #(model, commands) =
                restructure(Model(..model, editor:), structure)
              #(model, [Complete, ..commands])
            }
          }
      }
  }
}

fn changed(model: Model, structure: Structure, result) {
  case result {
    Ok(buffer) ->
      restructure(
        Model(..model, editor: editor.new(), choices: []),
        Structure(..structure, buffer:, input: None),
      )
    Error(message) -> #(Model(..model, status: message), [])
  }
}

/// Keep a changed structure, type checked with the references loaded so far,
/// and load the types of new references.
fn restructure(model: Model, structure: Structure) {
  case model.shell {
    None -> #(model, [])
    Some(shell) -> {
      let buffer =
        structural.reanalyse(structure.buffer, shell.scope, model.references)
      let missing =
        structural.references(buffer)
        |> list.unique
        |> list.filter(fn(reference) {
          result.is_error(list.key_find(model.references, reference))
          && !list.contains(model.loading, reference)
        })
      let status = case model.busy {
        True -> "Running…"
        False -> "Ready"
      }
      #(
        Model(
          ..model,
          structure: Some(Structure(..structure, buffer:)),
          loading: list.append(model.loading, missing),
          status:,
        ),
        list.map(missing, Load),
      )
    }
  }
}

/// The type of a referenced module, or why it could not be loaded.
pub fn loaded(model: Model, reference, type_) {
  let model =
    Model(
      ..model,
      loading: list.filter(model.loading, fn(r) { r != reference }),
    )
  let model = case type_ {
    Ok(type_) ->
      Model(..model, references: [#(reference, type_), ..model.references])
    Error(message) -> Model(..model, status: message)
  }
  case model.structure {
    Some(structure) -> {
      let #(updated, commands) = restructure(model, structure)
      #(Model(..updated, status: model.status), commands)
    }
    None -> #(model, [])
  }
}

/// The structure as readable source, for the history.
pub fn projection_text(structure: Structure) {
  structural.display_text(structure.buffer)
}

// The shell

pub fn started(model: Model, shell) {
  Model(..model, shell: Some(shell), busy: False, status: "Ready")
}

pub fn received(model: Model, id, event) {
  change(model, id, fn(entry) {
    case event {
      shell.Output(text, _) -> Entry(..entry, output: entry.output <> text)
      shell.Fetched(url) ->
        Entry(..entry, fetches: list.append(entry.fetches, [url]))
    }
  })
}

/// The shell asked for input while evaluating.
pub fn asked(model: Model, prompt) {
  let prompt = case prompt {
    "" -> "Input requested"
    _ -> prompt
  }
  Model(
    ..model,
    prompt: Some(#(prompt, model.editor)),
    editor: editor.new(),
    choices: [],
    status: "Waiting for input",
  )
}

/// An evaluation finished. A structure that evaluated without errors makes
/// way for a new one, and up returns to it.
pub fn completed(model: Model, id, evaluated: shell.Evaluated, duration) {
  let shell.Evaluated(results:, performed:, shell:) = evaluated
  let model =
    change(model, id, fn(entry) {
      Entry(
        ..entry,
        results:,
        performed:,
        duration: Some(duration),
        busy: False,
      )
    })
  let status = case shell.pending {
    "" -> "Ready"
    _ -> "Continue the expression…"
  }
  let shell = case model.shell {
    Some(before) -> shell.with_ledger(shell, before.execution)
    None -> shell
  }
  let model = Model(..model, shell: Some(shell), busy: False, status:)
  let cleared = case find(model, id), model.structure {
    Ok(Entry(structural: True, ..)), Some(structure) ->
      case list.all(results, result.is_ok) {
        True ->
          Some(Structure(
            buffer: structural.empty(shell.scope, shell.execution),
            input: None,
            previous: [structure.buffer, ..structure.previous],
            after: None,
            imported: structure.imported,
          ))
        False -> None
      }
    _, _ -> None
  }
  case cleared {
    Some(structure) -> restructure(model, structure)
    None -> #(model, [])
  }
}

pub fn failed(model: Model, id, message) {
  let editor = case model.prompt {
    Some(#(_, draft)) -> draft
    None -> model.editor
  }
  let model =
    change(model, id, fn(entry) {
      Entry(..entry, results: [Error(message)], busy: False)
    })
  Model(..model, busy: False, prompt: None, editor:, status: message)
}

pub fn find(model: Model, id) {
  list.find(model.entries, fn(entry) { entry.id == id })
}

pub fn has_effects(entry: Entry) {
  entry.performed != [] || entry.fetches != []
}

fn change(model: Model, id, change) {
  Model(
    ..model,
    entries: list.map(model.entries, fn(entry) {
      case entry.id == id {
        True -> change(entry)
        False -> entry
      }
    }),
  )
}
