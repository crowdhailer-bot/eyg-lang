//// What the tui shows, and how keys and the shell change it. Nothing here
//// performs effects: changes that need the outside world are commands for the
//// tui loop.

import eyg/analysis/type_/binding
import eyg/cli/tui/agent.{type Agent}
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
import overlay/llm/tool

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
    role: Role,
    name: String,
    code_expanded: Bool,
    output_expanded: Bool,
  )
}

/// Who an entry in the history is from.
pub type Role {
  Repl
  User
  Assistant
  Tool
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
    overlay: Bool,
    agent: Option(Agent),
    calls: List(#(tool.Call, Int)),
    turn: Int,
  )
}

/// Something a click on the screen does.
pub type Click {
  ToggleEffects(Int)
  ToggleCode(Int)
  ToggleOutput(Int)
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
  /// Send the person's message to the agent, its reply streaming into the entry.
  Ask(id: Int, text: String)
  Generate(id: Int)
  Call(id: Int, call: tool.Call, index: Int)
  /// Save the trajectory of the turn that started with the entry.
  Save(id: Int)
  Export(id: Int, path: String)
}

pub fn new(directory, overlay) {
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
    overlay:,
    agent: None,
    calls: [],
    turn: 0,
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
    "ctrl+o", _ ->
      case
        list.find(list.reverse(model.entries), fn(entry) { entry.role == Tool })
      {
        Ok(entry) -> click(model, ToggleCode(entry.id))
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
    ToggleCode(id) -> #(
      change(model, id, fn(entry) {
        Entry(..entry, code_expanded: !entry.code_expanded)
      }),
      [Reveal("code-" <> int.to_string(id))],
    )
    ToggleOutput(id) -> #(
      change(model, id, fn(entry) {
        Entry(..entry, output_expanded: !entry.output_expanded)
      }),
      [Reveal("code-" <> int.to_string(id))],
    )
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
        _ if model.overlay -> ask(Model(..model, editor: editor.new()), source)
        _ -> run(Model(..model, editor: editor.new()), source, Text(source))
      }
  }
}

/// Start an evaluation, shown in the history as `source`.
fn run(model: Model, source, code) {
  case model.shell, model.busy {
    Some(_), False -> {
      let structural = case code {
        Text(_) -> False
        Ir(_) -> True
      }
      let #(model, id) = append(model, source, Repl)
      let model = change(model, id, fn(entry) { Entry(..entry, structural:) })
      #(Model(..model, busy: True, choices: [], status: "Running…"), [
        FollowTail,
        Evaluate(id, code),
      ])
    }
    _, _ -> #(model, [])
  }
}

/// Add a busy entry to the history.
fn append(model: Model, source, role) {
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
      structural: False,
      role:,
      name: "",
      code_expanded: False,
      output_expanded: False,
    )
  #(
    Model(..model, entries: list.append(model.entries, [entry]), sequence: id),
    id,
  )
}

// Overlay

pub fn agent_started(model: Model, agent) {
  Model(..model, agent: Some(agent), busy: False, status: "Ready")
}

/// A message for the agent starts a turn: the reply streams into a new entry,
/// then each tool it calls runs in turn until it replies without calls.
fn ask(model: Model, text) {
  case model.agent {
    None -> #(model, [])
    Some(_) -> {
      let #(model, turn) = append(model, text, User)
      let model = change(model, turn, fn(entry) { Entry(..entry, busy: False) })
      let model =
        Model(..model, busy: True, turn:, choices: [], status: "Running…")
      case text {
        "/export" -> #(model, [FollowTail, Export(turn, "")])
        "/export " <> path -> #(model, [
          FollowTail,
          Export(turn, string.trim(path)),
        ])
        _ -> {
          let #(model, id) = append(model, "", Assistant)
          #(model, [FollowTail, Ask(id, text)])
        }
      }
    }
  }
}

/// The agent finished replying in the entry.
pub fn generated(model: Model, id, result, agent) {
  let model = Model(..model, agent: Some(agent))
  let model = case result {
    Error(reason) ->
      change(model, id, fn(entry) {
        Entry(..entry, results: [Error(reason)], busy: False)
      })
    Ok(_) -> change(model, id, fn(entry) { Entry(..entry, busy: False) })
  }
  // A reply that only calls tools has no text to show.
  let model = case find(model, id) {
    Ok(Entry(output: "", results: [], ..)) ->
      Model(
        ..model,
        entries: list.filter(model.entries, fn(entry) { entry.id != id }),
      )
    _ -> model
  }
  case result {
    Ok([_, ..] as calls) ->
      next_call(
        Model(
          ..model,
          calls: list.index_map(calls, fn(call, index) { #(call, index) }),
        ),
      )
    _ -> #(model, [Save(model.turn)])
  }
}

fn next_call(model: Model) {
  case model.calls {
    [] -> {
      let #(model, id) = append(model, "", Assistant)
      #(model, [Generate(id)])
    }
    [#(call, index), ..calls] -> {
      let #(model, id) = append(model, agent.code(call), Tool)
      let model =
        change(model, id, fn(entry) { Entry(..entry, name: call.function.name) })
      #(Model(..model, calls:), [Call(id, call, index)])
    }
  }
}

/// A tool call finished; the next one runs, or the agent replies again.
pub fn called(model: Model, id, result, performed, agent, duration) {
  change(model, id, fn(entry) {
    Entry(
      ..entry,
      results: [result],
      performed:,
      duration: Some(duration),
      busy: False,
    )
  })
  |> fn(model) { Model(..model, agent: Some(agent)) }
  |> next_call
}

/// The turn's trajectory was saved, or could not be.
pub fn saved(model: Model, result) {
  let line = case result {
    Ok(path) -> "trace saved to " <> path <> "\n"
    Error(reason) -> "Unable to save trace: " <> reason <> "\n"
  }
  change(model, model.turn, fn(entry) {
    Entry(..entry, output: entry.output <> line)
  })
  |> fn(model) { Model(..model, busy: False, status: "Ready") }
}

// Structural editing

/// F2 moves between text and structure. Text that was not changed since it
/// became a structure returns to that structure.
fn switch(model: Model) {
  case
    model.overlay || model.busy || model.prompt != None,
    model.structural,
    model.shell
  {
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
      // An assistant's requests are to its model, not the hub.
      shell.Fetched(_) if entry.role == Assistant -> entry
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
