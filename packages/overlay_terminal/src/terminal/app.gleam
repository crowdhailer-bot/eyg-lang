//// Shared interaction state. Renderer packages choose how changes reach
//// native widgets; this module does not know about OpenTUI or a UI framework.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import terminal/completion.{type Completion}
import terminal/protocol as p

pub type Role {
  Repl
  User
  Assistant
  Tool
}

pub type Entry {
  Entry(
    id: Int,
    source: String,
    output: String,
    results: List(Result(String, String)),
    effects: List(p.EffectRecord),
    fetches: List(String),
    duration: Option(Float),
    expanded: Bool,
    busy: Bool,
    role: Role,
    name: String,
    code_expanded: Bool,
    output_expanded: Bool,
  )
}

pub type Model {
  Model(
    overlay: Bool,
    ready: Bool,
    busy: Bool,
    entries: List(Entry),
    packages: List(String),
    source: String,
    cursor: Int,
    status: String,
    prompt: Option(String),
    choices: List(Completion),
    choice: Int,
    help: Bool,
    model_name: String,
    structural: Bool,
    structure: Option(p.View),
    sequence: Int,
    completion_revision: Int,
    prompt_draft: String,
    text_draft: String,
    imported_draft: Option(String),
    clipboard: String,
    entering_structure: Bool,
  )
}

pub type Message {
  Received(p.Event)
  Changed(String, Int)
  CompletedChoices(Int, List(Completion))
  Submit
  SwitchMode
  ToggleHelp
  ToggleEffects(Int)
  ToggleCode(Int)
  ToggleOutput(Int)
  Choose(Int)
  AcceptChoice
  DismissChoices
  StructuralAction(p.Action)
  Paste(String)
  ReadClipboard
  Page(Int)
  Quit
  Status(String)
  Noop
}

pub type Command {
  Send(p.Request)
  Editor(text: String, select_all: Bool, cursor_prefix: Option(String))
  Complete(revision: Int)
  FollowTail
  Reveal(String)
  Scroll(Int)
  Copy(String)
  Clipboard
  Exit
}

pub fn new(overlay) {
  Model(
    overlay:,
    ready: False,
    busy: False,
    entries: [],
    packages: [],
    source: "",
    cursor: 0,
    status: "Starting EYG…",
    prompt: None,
    choices: [],
    choice: 0,
    help: False,
    model_name: "",
    structural: False,
    structure: None,
    sequence: 0,
    completion_revision: 0,
    prompt_draft: "",
    text_draft: "",
    imported_draft: None,
    clipboard: "",
    entering_structure: False,
  )
}

pub fn input(model: Model) {
  case model.structural, model.structure {
    True, Some(view) -> view.input
    _, _ -> None
  }
}

pub fn editor_visible(model: Model) {
  !model.structural
  || option.is_some(input(model))
  || option.is_some(model.prompt)
}

pub fn entry(id, source, role) {
  Entry(
    id:,
    source:,
    role:,
    output: "",
    results: [],
    effects: [],
    fetches: [],
    duration: None,
    expanded: False,
    busy: True,
    name: "",
    code_expanded: False,
    output_expanded: False,
  )
}

pub fn update(model: Model, message: Message) -> #(Model, List(Command)) {
  case message {
    Noop -> #(model, [])
    Quit -> #(model, [Exit])
    Status(status) -> #(Model(..model, status:), [])
    ToggleHelp -> #(Model(..model, help: !model.help), [])
    Page(delta) -> #(model, [Scroll(delta)])
    Received(event) -> receive(model, event)
    Changed(source, cursor) -> {
      let revision = model.completion_revision + 1
      #(Model(..model, source:, cursor:, completion_revision: revision), [
        Complete(revision),
      ])
    }
    CompletedChoices(revision, choices) ->
      case revision == model.completion_revision {
        True -> #(Model(..model, choices:, choice: 0), [])
        False -> #(model, [])
      }
    Submit -> submit(model)
    SwitchMode -> switch_mode(model)
    ToggleEffects(id) -> {
      let model =
        change_entry(model, id, fn(entry) {
          Entry(..entry, expanded: !entry.expanded)
        })
      let expanded =
        find_entry(model, id)
        |> result.map(fn(entry) { entry.expanded })
        |> result.unwrap(False)
      #(model, [
        Reveal(
          case expanded {
            True -> "details-"
            False -> "effects-"
          }
          <> int.to_string(id),
        ),
      ])
    }
    ToggleCode(id) -> #(
      change_entry(model, id, fn(entry) {
        Entry(..entry, code_expanded: !entry.code_expanded)
      }),
      [Reveal("code-" <> int.to_string(id))],
    )
    ToggleOutput(id) -> #(
      change_entry(model, id, fn(entry) {
        Entry(..entry, output_expanded: !entry.output_expanded)
      }),
      [Reveal("code-" <> int.to_string(id))],
    )
    Choose(delta) -> {
      let count = list.length(model.choices)
      let choice = case count {
        0 -> 0
        _ -> { model.choice + delta + count } % count
      }
      #(Model(..model, choice:), [])
    }
    AcceptChoice ->
      case model.choices |> list.drop(model.choice) |> list.first {
        Error(_) -> #(model, [])
        Ok(choice) -> {
          let #(source, prefix) = completion.apply(model.source, choice)
          #(
            Model(..model, source:, cursor: string.length(prefix), choices: []),
            [Editor(source, False, Some(prefix))],
          )
        }
      }
    DismissChoices -> #(Model(..model, choices: []), [])
    StructuralAction(action) -> #(model, [Send(p.Structure(action))])
    Paste(text) ->
      case model.structural && input(model) == None && model.prompt == None {
        True -> #(model, [Send(p.Structure(p.Paste(text)))])
        False -> #(model, [])
      }
    ReadClipboard -> #(model, [Clipboard])
  }
}

pub fn find_entry(model: Model, id) {
  list.find(model.entries, fn(entry) { entry.id == id })
}

fn change_entry(model: Model, id, change) {
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

fn append_entry(model: Model, entry) {
  Model(..model, entries: list.append(model.entries, [entry]))
}

fn receive(model: Model, event: p.Event) -> #(Model, List(Command)) {
  case event {
    p.Ready(packages) -> #(
      Model(..model, ready: True, packages:, status: "Ready"),
      [],
    )
    p.OverlayReady(model_name) -> #(
      Model(..model, ready: True, model_name:, status: "Ready"),
      [],
    )
    p.Packages(packages) -> #(Model(..model, packages:), [
      Complete(model.completion_revision),
    ])
    p.Clipboard(text) -> #(Model(..model, clipboard: text), [Copy(text)])
    p.Assistant(id, text) -> {
      let model = case find_entry(model, id) {
        Error(_) ->
          append_entry(
            model,
            Entry(..entry(id, "", Assistant), output: text, busy: False),
          )
        Ok(_) ->
          change_entry(model, id, fn(entry) {
            Entry(..entry, output: entry.output <> text)
          })
      }
      #(model, [])
    }
    p.Tool(id, name, code) -> #(
      append_entry(model, Entry(..entry(id, code, Tool), name:)),
      [],
    )
    p.ToolResult(id, text, error, duration) -> #(
      change_entry(model, id, fn(entry) {
        Entry(
          ..entry,
          results: [
            case error {
              True -> Error(text)
              False -> Ok(text)
            },
          ],
          busy: False,
          duration: Some(duration),
        )
      }),
      [],
    )
    p.Output(id, text, _) -> #(
      change_entry(model, id, fn(entry) {
        Entry(..entry, output: entry.output <> text)
      }),
      [],
    )
    p.Fetch(id, url) -> #(
      change_entry(model, id, fn(entry) {
        Entry(..entry, fetches: list.append(entry.fetches, [url]))
      }),
      [],
    )
    p.Effect(id, effect) -> #(
      change_entry(model, id, fn(entry) {
        Entry(..entry, effects: list.append(entry.effects, [effect]))
      }),
      [],
    )
    p.Prompt(_, text) -> #(
      Model(
        ..model,
        prompt_draft: model.source,
        source: "",
        cursor: 0,
        prompt: Some(case text {
          "" -> "Input requested"
          _ -> text
        }),
        status: "Waiting for input",
        choices: [],
      ),
      [Editor("", False, None)],
    )
    p.Complete(id, results, pending, duration) -> {
      let model =
        change_entry(model, id, fn(entry) {
          Entry(..entry, results:, duration: Some(duration), busy: False)
        })
      #(
        Model(..model, busy: False, prompt: None, status: case pending {
          "" -> "Ready"
          _ -> "Continue the expression…"
        }),
        [],
      )
    }
    p.Failure(id, message) -> {
      let commands = case model.entering_structure {
        True -> [Editor(model.text_draft, False, None)]
        False -> []
      }
      let model = case model.entering_structure {
        True ->
          Model(
            ..model,
            entering_structure: False,
            imported_draft: None,
            structural: False,
            source: model.text_draft,
          )
        False -> model
      }
      let model = case id {
        0 -> model
        _ ->
          change_entry(model, id, fn(entry) {
            Entry(..entry, results: [Error(message)], busy: False)
          })
      }
      #(
        Model(
          ..model,
          status: message,
          busy: False,
          entries: list.map(model.entries, fn(entry) {
            case entry.busy {
              True -> Entry(..entry, busy: False)
              False -> entry
            }
          }),
        ),
        commands,
      )
    }
    p.Structural(view) -> {
      let previous = input(model)
      let commands = case model.structural, model.prompt, previous, view.input {
        True, None, None, Some(input) -> [
          Editor(input.value, input.kind == "text", None),
        ]
        True, None, Some(before), Some(input) if before.label != input.label -> [
          Editor(input.value, input.kind == "text", None),
        ]
        True, None, _, None -> [Editor("", False, None)]
        _, _, _, _ -> []
      }
      let source = case commands {
        [Editor(text, _, _), ..] -> text
        _ -> model.source
      }
      let status =
        option.unwrap(view.message, case model.prompt, model.busy {
          Some(_), _ -> "Waiting for input"
          _, True -> "Running…"
          _, _ -> "Ready"
        })
      #(
        Model(
          ..model,
          structure: Some(view),
          source:,
          status:,
          entering_structure: False,
        ),
        commands,
      )
    }
  }
}

fn submit(model: Model) {
  case model.prompt, input(model) {
    Some(_), _ -> #(
      Model(
        ..model,
        prompt: None,
        source: model.prompt_draft,
        prompt_draft: "",
        status: "Running…",
      ),
      [Send(p.Reply(model.source)), Editor(model.prompt_draft, False, None)],
    )
    _, Some(_) -> #(model, [Send(p.Structure(p.Answer(model.source)))])
    _, None -> {
      let source = case model.structural, model.structure {
        True, Some(view) -> view.source
        _, _ -> model.source
      }
      case model.ready, model.busy, string.trim(source) {
        False, _, _ | _, True, _ | _, _, "" -> #(model, [])
        _, _, "/exit" -> #(model, [Exit])
        _, _, _ -> {
          let id = model.sequence + 1
          let model =
            append_entry(
              model,
              entry(id, source, case model.overlay {
                True -> User
                False -> Repl
              }),
            )
          #(
            Model(
              ..model,
              busy: True,
              source: "",
              cursor: 0,
              choices: [],
              sequence: id,
              status: "Running…",
            ),
            [
              FollowTail,
              Editor("", False, None),
              Send(p.Evaluate(id, source, model.structural)),
            ],
          )
        }
      }
    }
  }
}

fn switch_mode(model: Model) {
  case
    model.overlay || model.busy || option.is_some(model.prompt) || !model.ready
  {
    True -> #(model, [])
    False ->
      case model.structural {
        True -> #(
          Model(
            ..model,
            structural: False,
            source: model.text_draft,
            choices: [],
          ),
          [Editor(model.text_draft, False, None)],
        )
        False -> {
          let source = case model.imported_draft == Some(model.source) {
            True -> None
            False -> Some(model.source)
          }
          #(
            Model(
              ..model,
              structural: True,
              text_draft: model.source,
              source: "",
              imported_draft: Some(model.source),
              entering_structure: True,
              choices: [],
            ),
            [Editor("", False, None), Send(p.Structure(p.Enter(source)))],
          )
        }
      }
  }
}

/// Return Some only when the global handler should prevent native input.
pub fn key(model: Model, name, sequence, ctrl, shift, _meta) {
  case name, ctrl {
    "c", True -> Some(Quit)
    "f1", _ -> Some(ToggleHelp)
    "f2", _ -> Some(SwitchMode)
    "e", True ->
      Some(latest(
        model.entries,
        fn(entry) {
          !list.is_empty(entry.effects) || !list.is_empty(entry.fetches)
        },
        ToggleEffects,
      ))
    "o", True ->
      Some(latest(model.entries, fn(entry) { entry.role == Tool }, ToggleCode))
    "pageup", _ -> Some(Page(-12))
    "pagedown", _ -> Some(Page(12))
    _, _ -> {
      case model.structural, model.prompt, input(model), name {
        True, None, Some(_), "escape" -> Some(StructuralAction(p.Cancel))
        True, None, None, "escape" -> Some(SwitchMode)
        True, None, None, _ -> {
          let command = case name, string.length(sequence), shift {
            "space", _, _ -> " "
            _, 1, _ -> sequence
            _, _, True -> string.uppercase(name)
            _, _, _ -> name
          }
          Some(case model.busy, name, command {
            True, _, _ -> Noop
            _, "return", _ -> Submit
            _, _, "Y" -> ReadClipboard
            _, _, _ -> StructuralAction(p.Key(command))
          })
        }
        _, _, _, _ ->
          case list.is_empty(model.choices), name {
            False, "tab" -> Some(AcceptChoice)
            False, "up" -> Some(Choose(-1))
            False, "down" -> Some(Choose(1))
            False, "escape" -> Some(DismissChoices)
            _, _ -> None
          }
      }
    }
  }
}

fn latest(entries, predicate, message) {
  entries
  |> list.reverse
  |> list.find(predicate)
  |> result.map(fn(entry: Entry) { message(entry.id) })
  |> result.unwrap(Noop)
}
