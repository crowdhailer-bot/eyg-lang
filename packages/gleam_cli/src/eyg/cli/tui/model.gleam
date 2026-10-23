//// What the tui shows, and how keys and the shell change it. Nothing here
//// performs effects: changes that need the outside world are commands for the
//// tui loop.

import eyg/cli/tui/completion.{type Completion}
import eyg/cli/tui/editor.{type Editor}
import eyg/cli/tui/shell
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

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
  )
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
  )
}

/// Something a click on the screen does.
pub type Click {
  ToggleEffects(Int)
}

pub type Command {
  Evaluate(id: Int, source: String)
  Answer(String)
  Quit
  FollowTail
  Reveal(String)
  Scroll(Int)
  /// Find completions for the text being written.
  Complete
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
  )
}

pub fn key(model: Model, key: String) -> #(Model, List(Command)) {
  case key {
    "ctrl+c" -> #(model, [Quit])
    "f1" -> #(Model(..model, help: !model.help), [])
    "ctrl+e" ->
      case list.find(list.reverse(model.entries), has_effects) {
        Ok(entry) -> click(model, ToggleEffects(entry.id))
        Error(Nil) -> #(model, [])
      }
    "pageup" -> #(model, [Scroll(-12)])
    "pagedown" -> #(model, [Scroll(12)])
    "tab" if model.choices != [] -> accept(model)
    "up" if model.choices != [] -> #(choose(model, -1), [])
    "down" if model.choices != [] -> #(choose(model, 1), [])
    "esc" if model.choices != [] -> #(Model(..model, choices: []), [])
    _ ->
      case editor.key(model.editor, key) {
        editor.Edited(editor) -> edited(model, editor)
        editor.Submitted -> submit(model)
        editor.Ignored -> #(model, [])
      }
  }
}

pub fn paste(model: Model, text) {
  edited(model, editor.insert(model.editor, text))
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
      let editor = editor.Editor(text, string.length(prefix))
      #(Model(..model, editor:, choices: []), [])
    }
  }
}

/// Completions found for the text being written.
pub fn completed_choices(model: Model, choices) {
  Model(..model, choices:, choice: 0)
}

/// Published packages, to complete after `@`.
pub fn discovered(model: Model, packages) {
  #(Model(..model, packages:), [Complete])
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
  }
}

fn submit(model: Model) {
  let source = model.editor.text
  case model.prompt, model.shell != None && !model.busy, string.trim(source) {
    Some(#(_, draft)), _, _ -> #(
      Model(..model, prompt: None, editor: draft, status: "Running…"),
      [Answer(source)],
    )
    None, False, _ | None, _, "" -> #(model, [])
    None, True, "/exit" -> #(model, [Quit])
    None, True, _ -> {
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
        )
      #(
        Model(
          ..model,
          busy: True,
          entries: list.append(model.entries, [entry]),
          editor: editor.new(),
          choices: [],
          sequence: id,
          status: "Running…",
        ),
        [FollowTail, Evaluate(id, source)],
      )
    }
  }
}

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
  Model(..model, shell: Some(shell), busy: False, status: case shell.pending {
    "" -> "Ready"
    _ -> "Continue the expression…"
  })
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
