//// An agent is Jev editing a program towards a task, one choice at a time.
//// Each step builds a request describing the program and every available
//// edit, the chosen edit is then applied. No IO happens here.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev
import jev_playground/action.{type Action} as a
import jev_playground/environment.{type Environment}
import jev_playground/options
import jev_playground/run
import jev_playground/vocabulary
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/navigation
import morph/projection as p
import morph/text

pub type Agent {
  Agent(
    task: String,
    buffer: Buffer,
    environment: Environment,
    config: options.Config,
    /// Most recent step first.
    history: List(Step),
    test_results: Option(String),
    finished: Bool,
    /// Names and literals from the task, found once as the task can be long.
    task_vocabulary: vocabulary.Vocabulary,
    /// Recent program states, with the selection marked, and the edit chosen in each.
    visited: List(#(String, Action)),
  )
}

/// A choice Jev made, with what it was offered.
pub type Step {
  Step(
    action: Action,
    confidence: Float,
    /// The most likely options, highest probability first.
    ranked: List(#(String, Float)),
    offered: Int,
    input_tokens: Int,
    thinking_ms: Int,
    /// The edit could not be applied, for example a compound failing part way.
    failed: Bool,
    /// How the choice is shown, the option name with any name filled in.
    label: String,
  )
}

pub const selection = text.Mark("«", "»")

pub const question_id = "next_edit"

fn instructions(highlight) {
  let marked = case highlight {
    options.Guillemets | options.Excerpt ->
      "The selected code is marked with « and » in `program`."
    options.Comments ->
      "The selected code is between `/* selection */` and `/* end */` in `program`."
    options.Unmarked ->
      "Where the selected code is in `program` is described by `selection`."
  }
  "Choose the single next edit that makes the most progress towards completing the task. "
  <> marked
  <> " Most edits replace or wrap the selection, `?` marks code still to be written."
}

const recent_actions = 6

pub fn new(task, source: e.Expression, environment, config) -> Agent {
  // Start on the first hole of a scaffold, otherwise with everything selected.
  let projection = case source {
    e.Vacant -> p.all(source)
    _ -> navigation.next_vacant(p.all(source)) |> result.unwrap(p.all(source))
  }
  let buffer =
    buffer.from_projection(
      projection,
      environment.context(environment),
      environment.references(environment),
    )
  Agent(
    task:,
    buffer:,
    environment:,
    config:,
    history: [],
    test_results: None,
    finished: False,
    task_vocabulary: vocabulary.from_task(task),
    visited: [],
  )
}

pub fn with_task(agent: Agent, task) {
  Agent(..agent, task:, task_vocabulary: vocabulary.from_task(task))
}

pub fn source(agent: Agent) -> e.Expression {
  p.rebuild(agent.buffer.projection)
}

pub fn options(agent: Agent) -> List(options.Option) {
  let vocabulary = vocabulary.with_task(agent.task_vocabulary, source(agent))
  // Coming back to a state means the edit chosen there last time did not help.
  let repeated = case agent.config.no_repeats {
    True -> {
      let here = program_text(agent)
      list.filter_map(agent.visited, fn(entry) {
        case entry.0 == here {
          True -> Ok(options.without_name(entry.1))
          False -> Error(Nil)
        }
      })
    }
    False -> []
  }
  // The same kind of edit chosen many times in a row is usually a loop.
  let repeated = case
    agent.config.no_repeats,
    list.take(agent.history, in_a_row)
  {
    True, [first, ..] as recent ->
      case
        list.length(recent) == in_a_row
        && list.all(recent, fn(step) {
          options.without_name(step.action)
          == options.without_name(first.action)
        })
      {
        True -> [options.without_name(first.action), ..repeated]
        False -> repeated
      }
    _, _ -> repeated
  }
  // Moving back and making the same edit again and again is a loop that changes
  // the program every time, the step that would come next is not offered.
  // Taking turns without moving back is normal, as when nesting calls.
  let repeated = case agent.config.no_repeats, list.take(agent.history, 6) {
    True, [a1, b1, a2, b2, a3, b3] ->
      case
        a1.action == a2.action
        && a2.action == a3.action
        && b1.action == b2.action
        && b2.action == b3.action
        && a1.action != b1.action
        && { a.is_navigation(a1.action) || a.is_navigation(b1.action) }
      {
        True -> [options.without_name(b1.action), ..repeated]
        False -> repeated
      }
    _, _ -> repeated
  }
  let jumps = case agent.config.hole_jumps {
    True -> hole_jumps(agent.buffer, agent.environment)
    False -> []
  }
  let jumps = case agent.config.focus_holes && agent.config.argument_jumps {
    True -> list.append(jumps, argument_jumps(agent.buffer, agent.environment))
    False -> jumps
  }
  options.available(agent.buffer, agent.environment, vocabulary, opened(agent))
  |> list.append(jumps, _)
  |> list.filter(fn(option) {
    !list.contains(repeated, options.without_name(option.action))
  })
  // An edit waiting for text is asked for in its own question, which has to have candidates.
  |> list.filter(fn(option) {
    case options.slot(option.action) {
      Ok(slot) -> candidates(agent, slot) != []
      Error(Nil) -> True
    }
  })
  |> list.take(jev.max_choice_options)
}

// A library the program already references is open: its API is in the state and
// its functions are offered as calls, whether Jev opened it or wrote it in.
fn opened(agent: Agent) -> options.Config {
  let code = text.print(source(agent))
  let referenced =
    list.filter_map(agent.environment.libraries, fn(library) {
      case string.contains(code, "@" <> library.name <> ":") {
        True -> Ok(library.name)
        False -> Error(Nil)
      }
    })
  let open_libraries =
    list.append(agent.config.open_libraries, referenced) |> list.unique
  options.Config(..agent.config, open_libraries:)
}

// Moving to any other hole, described by where it is, so Jev can fill the holes
// in the order the task describes them.
fn hole_jumps(
  buffer: Buffer,
  environment: Environment,
) -> List(options.Option) {
  let here = p.path(buffer.projection)
  a.holes(buffer)
  |> list.index_map(fn(hole, i) { #(i + 1, hole) })
  |> list.filter(fn(hole) { p.path(hole.1) != here })
  |> list.take(8)
  |> list.map(fn(hole) {
    let #(number, projection) = hole
    let place = case
      role(buffer.update_position(buffer, projection), environment)
    {
      Ok(role) -> ", " <> role
      Error(Nil) -> ""
    }
    let action = a.JumpToHole(number)
    options.Option(
      action:,
      name: a.key(action),
      description: "Select hole " <> int.to_string(number) <> place <> ".",
    )
  })
}

// When the program is complete each argument of a call can be selected by its
// code, so one that is wrong can be changed after seeing what the program returns.
fn argument_jumps(
  buffer: Buffer,
  environment: Environment,
) -> List(options.Option) {
  case a.holes(buffer) {
    [] ->
      calls(p.rebuild(buffer.projection), [], [])
      |> list.reverse
      |> list.flat_map(fn(call) {
        case call {
          #(e.Call(_, args), path) ->
            list.index_map(args, fn(arg, i) {
              #(arg, list.append(path, [i + 1]))
            })
          _ -> []
        }
      })
      // Selecting what is already selected is not an edit, and only a literal is
      // worth going back to: an argument that is wrong is usually one of those.
      |> list.filter(fn(argument) {
        let #(exp, path) = argument
        path != p.path(buffer.projection)
        && case exp {
          e.String(_) | e.Integer(_) -> True
          _ -> False
        }
      })
      |> list.filter_map(fn(argument) {
        let #(exp, path) = argument
        use moved <- result.map(buffer.focus_at(buffer, path))
        let place = case role(moved, environment) {
          Ok(role) -> ", " <> role
          Error(Nil) -> ""
        }
        let action = a.JumpTo(path, short(exp))
        options.Option(
          action:,
          name: a.key(action),
          description: "Select `"
            <> short(exp)
            <> "`"
            <> place
            <> ", to change it.",
        )
      })
      |> list.fold([], fn(kept, option) {
        case list.any(kept, fn(k: options.Option) { k.name == option.name }) {
          True -> kept
          False -> [option, ..kept]
        }
      })
      |> list.reverse
      |> list.take(8)
    _ -> []
  }
}

const remembered_states = 12

const in_a_row = 5

pub fn program_text(agent: Agent) {
  let projection = agent.buffer.projection
  text.marked(p.rebuild(projection), [
    #(p.path(projection), selection),
    ..hole_marks(agent)
  ])
  |> shown(agent)
}

// The program as Jev sees it, with the selection shown as configured.
fn shown_program(agent: Agent) {
  let projection = agent.buffer.projection
  let path = p.path(projection)
  let marks = case agent.config.highlight {
    options.Guillemets | options.Excerpt -> [#(path, selection)]
    options.Comments -> [
      #(path, text.Mark("/* selection */ ", " /* end */")),
    ]
    options.Unmarked -> []
  }
  text.marked(p.rebuild(projection), list.append(marks, hole_marks(agent)))
  |> shown(agent)
}

// A release is read and written as its package name, the content id is noise
// in a program Jev has to read.
fn shown(code, agent: Agent) {
  environment.shorten_packages(code, agent.environment)
}

fn hole_marks(agent) {
  list.map(extra_holes(agent), fn(hole) {
    #(p.path(hole.1), text.Mark("⟨" <> int.to_string(hole.0) <> ":", "⟩"))
  })
}

/// Holes after the selection that Jev is asked to fill in the same request,
/// with the number each is shown with. Only in hole mode with several cursors.
pub fn extra_holes(agent: Agent) -> List(#(Int, p.Projection)) {
  let Agent(buffer:, config:, ..) = agent
  case config.focus_holes && config.cursors > 1, buffer.projection {
    True, #(p.Exp(e.Vacant), _) -> {
      let here = p.path(buffer.projection)
      let numbered =
        list.index_map(a.holes(buffer), fn(hole, i) { #(i + 1, hole) })
      let #(before, after) =
        list.split_while(numbered, fn(hole) { p.path(hole.1) != here })
      list.append(list.drop(after, 1), before)
      |> list.take(config.cursors - 1)
    }
    _, _ -> []
  }
}

const leave = "leave it for later"

fn cursor_id(number) {
  "hole_" <> int.to_string(number)
}

// What could fill each extra hole, only edits that need no further question.
fn cursor_options(agent: Agent) {
  let vocabulary = vocabulary.with_task(agent.task_vocabulary, source(agent))
  list.map(extra_holes(agent), fn(hole) {
    let #(number, projection) = hole
    let at = buffer.update_position(agent.buffer, projection)
    let offered =
      options.available(at, agent.environment, vocabulary, agent.config)
      |> list.filter(fn(option) { is_fill(option.action) })
      |> list.take(jev.max_choice_options - 1)
    #(number, projection, offered)
  })
}

// The question for an extra hole says where the hole is and its type, as the
// selection description only describes the selected hole.
fn cursor_question(
  number,
  at: Buffer,
  offered: List(options.Option),
  environment: Environment,
) {
  let role = case role(at, environment) {
    Ok(role) -> ", " <> role
    Error(Nil) -> ""
  }
  let type_ = case buffer.target_type(at) {
    Ok(t.Var(_)) | Error(Nil) -> ""
    Ok(type_) -> ", of type " <> environment.show_type(type_)
  }
  let instructions =
    "Choose what fills the hole marked ⟨"
    <> int.to_string(number)
    <> ":?⟩ in `program`"
    <> role
    <> type_
    <> ", or leave it for later if the task does not yet say."
  let criteria =
    list.map(offered, fn(option) {
      #(options.key(option), Some(json.string(option.description)))
    })
  jev.Choice(json.string(instructions), [
    #(leave, Some(json.string("Do not fill this hole yet."))),
    ..criteria
  ])
}

// An edit that fills the selection, rather than moving, checking or undoing.
fn is_fill(action) {
  case action {
    a.RunTests
    | a.Finish
    | a.Undo
    | a.Delete
    | a.OpenLibrary(_)
    | a.ChooseString
    | a.ChooseInteger -> False
    _ -> !a.is_navigation(action) && options.slot(action) == Error(Nil)
  }
}

/// The state given to Jev, everything it needs to judge the next edit.
pub fn state(agent: Agent) -> Json {
  let Agent(task:, buffer:, environment:, config:, history:, test_results:, ..) =
    agent
  let errors =
    list.index_map(a.type_errors(buffer), fn(error, i) {
      let #(_rev, reason) = error
      int.to_string(i + 1) <> ": " <> options.describe_error(reason)
    })
  let libraries =
    list.filter_map(config.open_libraries, fn(name) {
      use library <- result.map(environment.find_library(environment, name))
      let api =
        environment.library_api(library)
        |> list.map(fn(field) { #(field.0, json.string(field.1)) })
      #("@" <> name, json.object(api))
    })
  let recent =
    history
    |> list.take(recent_actions)
    |> list.reverse
    |> list.map(fn(step) {
      case step.failed {
        True -> json.string(a.key(step.action) <> " (failed, nothing changed)")
        False -> json.string(a.key(step.action))
      }
    })
  json.object(
    list.flatten([
      [
        #("task", json.string(task)),
        #("program", json.string(shown_program(agent))),
        #("selection", selection_json(buffer, config, environment)),
        #("type_errors", json.array(errors, json.string)),
      ],
      case config.context_readme, environment.context_readme(environment) {
        True, Some(readme) -> [#("context", json.string(readme))]
        _, _ -> []
      },
      case config.hole_types {
        True -> [#("holes", json.array(hole_types(buffer), json.string))]
        False -> []
      },
      case environment.effects, config.effects {
        [], _ | _, options.NoEffects | _, options.EffectCallsOnly -> []
        _, options.EffectNodes -> [
          #(
            "effects",
            json.object(
              list.map(environment.effect_signatures(environment), fn(effect) {
                #(effect.0, json.string(effect.1))
              }),
            ),
          ),
          #("effects_performed", json.array(effect_nodes(buffer), json.string)),
        ]
        _, _ -> [
          #(
            "effects",
            json.object(
              list.map(environment.effect_signatures(environment), fn(effect) {
                #(effect.0, json.string(effect.1))
              }),
            ),
          ),
        ]
      },
      case libraries {
        [] -> []
        _ -> [#("libraries", json.object(libraries))]
      },
      case test_results {
        Some(results) -> [#("last_run", json.string(results))]
        None -> []
      },
      [#("recent_edits", json.preprocessed_array(recent))],
    ]),
  )
}

// The type each hole must have, so Jev can see what fits beyond the selection.
fn hole_types(buffer: Buffer) -> List(String) {
  let here = p.path(buffer.projection)
  list.index_map(a.holes(buffer), fn(hole, i) {
    let path = p.path(hole)
    let type_ = case infer.type_at(buffer.analysis, list.reverse(path)) {
      Ok(t.Var(_)) | Error(Nil) -> "any type"
      Ok(type_) -> environment.show_type(type_)
    }
    let selected = case path == here {
      True -> " (selected)"
      False -> ""
    }
    int.to_string(i + 1) <> selected <> ": " <> type_
  })
}

fn selection_json(
  buffer: Buffer,
  config: options.Config,
  environment: Environment,
) {
  let code = case config.highlight, buffer.projection {
    options.Excerpt, #(p.Exp(exp), _) | options.Unmarked, #(p.Exp(exp), _) -> [
      #(
        "code",
        json.string(environment.shorten_packages(text.print(exp), environment)),
      ),
    ]
    _, _ -> []
  }
  let type_ = case buffer.target_type(buffer) {
    Ok(t.Var(_)) | Error(Nil) -> []
    Ok(type_) -> [#("type", json.string(environment.show_type(type_)))]
  }
  let role = case role(buffer, environment) {
    Ok(role) -> [#("role", json.string(role))]
    Error(Nil) -> []
  }
  let performs = case config.effects {
    options.EffectNodes ->
      case effects_at(buffer, p.path(buffer.projection)) {
        [] -> []
        labels -> [#("performs", json.string(string.join(labels, ", ")))]
      }
    _ -> []
  }
  json.object([
    #("kind", json.string(options.focus_kind(buffer))),
    ..list.flatten([code, role, type_, performs])
  ])
}

// Where the selection sits in its parent, so the position of a hole is clear.
fn role(buffer: Buffer, environment: Environment) -> Result(String, Nil) {
  let short = fn(exp) {
    let code =
      text.print(exp)
      |> environment.shorten_packages(environment)
      |> string.replace("\n", " ")
    case string.length(code) > 40 {
      True -> string.slice(code, 0, 37) <> "..."
      False -> code
    }
  }
  case buffer.projection {
    #(p.Exp(_), [p.CallArg(func, pre, post), ..rest]) -> {
      let position = list.length(pre) + 1
      let count = position + list.length(post)
      let path = p.path_to_zoom(rest, [])
      let func_type = case
        infer.type_at(buffer.analysis, list.reverse(list.append(path, [0])))
      {
        Ok(type_) -> ", which has type " <> environment.show_type(type_)
        Error(Nil) -> ""
      }
      // The arguments of a context function are named by its parameters.
      let name = case func {
        e.Select(e.Variable("context"), label) ->
          case
            list.drop(environment.parameters(environment, label), position - 1)
          {
            [name, ..] -> ", `" <> name <> "`,"
            [] -> ""
          }
        _ -> ""
      }
      Ok(
        "argument "
        <> int.to_string(position)
        <> " of "
        <> int.to_string(count)
        <> name
        <> " to "
        <> short(func)
        <> func_type,
      )
    }
    // A match branch is a function, what it returns is the value for the branch.
    #(p.Exp(_), [p.Body(_), p.CaseMatch(label:, ..), ..]) ->
      Ok("the value returned when the match is `" <> label <> "`")
    #(p.Exp(_), [p.Body(_), p.CaseTail(..), ..]) ->
      Ok("the value returned when the match is any other tag")
    #(p.Exp(_), [p.Body(params), ..]) ->
      Ok(
        "the body of the function taking ("
        <> string.join(list.map(params, pattern_text), ", ")
        <> ")",
      )
    #(p.Exp(_), [p.BlockValue(pattern, ..), ..]) ->
      Ok("the value assigned to " <> pattern_text(pattern))
    #(p.Exp(_), [p.BlockTail(_), ..]) ->
      Ok("the value returned after the assignments")
    #(p.Exp(_), [p.RecordValue(label, ..), ..]) ->
      Ok("the value of the field `" <> label <> "`")
    #(p.Exp(_), [p.ListItem(pre, ..), ..]) ->
      Ok("item " <> int.to_string(list.length(pre) + 1) <> " of a list")
    #(p.Exp(_), [p.CaseMatch(label:, ..), ..]) ->
      Ok("the branch for `" <> label <> "`")
    _ -> Error(Nil)
  }
}

fn pattern_text(pattern) {
  case pattern {
    e.Bind(name) -> name
    e.Destructure(fields) ->
      "{" <> string.join(list.map(fields, fn(field) { field.1 }), ", ") <> "}"
  }
}

/// Asked alongside the edit when the program is complete and has run: Jev has
/// what it returned in the state and says whether that answers the task.
pub const answered_id = "answered"

pub const answers_task = "yes"

const keep_editing = "no"

fn answered_question() {
  jev.Choice(
    json.string(
      "`last_run` says what the finished program returned. Is that the answer to the task?",
    ),
    [
      #(
        answers_task,
        Some(json.string(
          "What the program returned is what the task asked for, stop here.",
        )),
      ),
      #(
        keep_editing,
        Some(json.string(
          "The task asks for something else, go on editing the program.",
        )),
      ),
    ],
  )
}

pub fn question(offered: List(options.Option), highlight) -> jev.Question {
  let criteria =
    list.map(offered, fn(option) {
      #(options.key(option), Some(json.string(option.description)))
    })
  jev.Choice(json.string(instructions(highlight)), criteria)
}

/// The candidates offered in the question for a slot.
pub fn candidates(agent: Agent, slot) -> List(String) {
  let vocabulary = vocabulary.with_task(agent.task_vocabulary, source(agent))
  options.candidates(slot, agent.buffer, vocabulary)
  |> list.filter(fn(text) { text != "" })
  |> list.unique
  |> list.take(jev.max_choice_options)
}

const slots = [
  options.NameSlot,
  options.LabelSlot,
  options.StringSlot,
  options.IntegerSlot,
]

/// The request for the next step and the options it offers.
/// When an edit needs a name it is asked for in a second question, evaluated in
/// parallel, so the options do not repeat each edit for every name.
pub fn request(
  agent: Agent,
  model: String,
) -> #(jev.Request, List(options.Option)) {
  let offered = options(agent)
  let slot_questions =
    list.filter_map(slots, fn(slot) {
      let needed =
        list.any(offered, fn(option) { options.slot(option.action) == Ok(slot) })
      case needed, candidates(agent, slot) {
        True, [_, ..] as candidates -> {
          let criteria = list.map(candidates, fn(text) { #(text, None) })
          let instructions = json.string(options.slot_instructions(slot))
          Ok(#(options.slot_id(slot), jev.Choice(instructions, criteria)))
        }
        _, _ -> Error(Nil)
      }
    })
  let ran = case
    agent.config.ask_answered,
    is_complete(agent),
    agent.test_results
  {
    True, True, Some(_) -> [#(answered_id, answered_question())]
    _, _, _ -> []
  }
  let request =
    jev.Request(model:, state: state(agent), questions: [
      #(question_id, question(offered, agent.config.highlight)),
      ..list.flatten([
        ran,
        slot_questions,
        list.map(cursor_options(agent), fn(cursor) {
          let #(number, projection, offered) = cursor
          let at = buffer.update_position(agent.buffer, projection)
          #(
            cursor_id(number),
            cursor_question(number, at, offered, agent.environment),
          )
        }),
      ])
    ])
  #(request, offered)
}

/// Apply the edit Jev chose.
pub fn answer(
  agent: Agent,
  offered: List(options.Option),
  evaluation: jev.Evaluation,
  thinking_ms: Int,
) -> Result(Agent, String) {
  use answer <- result.try(
    dict.get(evaluation.answers, question_id)
    |> result.replace_error("no answer to " <> question_id),
  )
  // Jev was asked whether what the program returned answers the task, which it
  // judges without the edits competing for the same choice.
  case dict.get(evaluation.answers, answered_id) {
    Ok(jev.ChoiceAnswer(choice:, probabilities:, confidence:))
      if choice == answers_task
    -> {
      let step =
        Step(
          action: a.Finish,
          label: a.key(a.Finish),
          confidence:,
          ranked: jev.ranked(probabilities) |> list.take(8),
          offered: list.length(offered),
          input_tokens: evaluation.usage.input_tokens,
          thinking_ms:,
          failed: False,
        )
      take(agent, step)
    }
    _ -> apply_edit(agent, offered, evaluation, thinking_ms, answer)
  }
}

fn apply_edit(
  agent: Agent,
  offered: List(options.Option),
  evaluation: jev.Evaluation,
  thinking_ms: Int,
  answer,
) -> Result(Agent, String) {
  case answer {
    jev.ChoiceAnswer(choice:, probabilities:, confidence:) -> {
      use option <- result.try(
        list.find(offered, fn(option) { options.key(option) == choice })
        |> result.replace_error("unknown option " <> choice),
      )
      use action <- result.try(case options.slot(option.action) {
        Ok(slot) ->
          case dict.get(evaluation.answers, options.slot_id(slot)) {
            Ok(jev.ChoiceAnswer(choice: text, ..)) ->
              Ok(options.fill(option.action, text))
            _ ->
              Error("no answer to the " <> options.slot_id(slot) <> " question")
          }
        Error(Nil) -> Ok(option.action)
      })
      let label = case options.slot(option.action) {
        Ok(_) -> a.key(action)
        Error(Nil) -> choice
      }
      let step =
        Step(
          action:,
          label:,
          confidence:,
          ranked: jev.ranked(probabilities) |> list.take(8),
          offered: list.length(offered),
          input_tokens: evaluation.usage.input_tokens,
          thinking_ms:,
          failed: False,
        )
      // A failed edit is shown to Jev in the recent edits rather than ending the run.
      case take(agent, step) {
        Ok(after) ->
          case is_fill(action) {
            True ->
              Ok(fill_extra_holes(after, cursor_options(agent), evaluation))
            False -> Ok(after)
          }
        Error(_) -> Ok(failed(agent, step))
      }
    }
    _ -> Error("expected a choice answer")
  }
}

fn failed(agent: Agent, step: Step) {
  let step = Step(..step, failed: True)
  let visited =
    [#(program_text(agent), step.action), ..agent.visited]
    |> list.take(remembered_states)
  Agent(..agent, history: [step, ..agent.history], visited:)
}

// Each extra hole Jev chose an edit for is filled as its own step, the tokens
// and time of the request are counted on the main step.
fn fill_extra_holes(agent, cursors, evaluation: jev.Evaluation) -> Agent {
  list.fold(cursors, agent, fn(agent, cursor) {
    let #(number, projection, offered) = cursor
    let chosen = case dict.get(evaluation.answers, cursor_id(number)) {
      Ok(jev.ChoiceAnswer(choice:, probabilities:, confidence:))
        if choice != leave
      -> {
        use option <- result.map(
          list.find(offered, fn(option) { options.key(option) == choice }),
        )
        let action = a.AtHole(p.path(projection), number, option.action)
        Step(
          action:,
          label: a.key(action),
          confidence:,
          ranked: jev.ranked(probabilities) |> list.take(8),
          offered: list.length(offered) + 1,
          input_tokens: 0,
          thinking_ms: 0,
          failed: False,
        )
      }
      _ -> Error(Nil)
    }
    case chosen {
      Ok(step) ->
        case take(agent, step) {
          Ok(agent) -> agent
          Error(_) -> failed(agent, step)
        }
      Error(Nil) -> agent
    }
  })
}

/// Apply an action as the next step.
pub fn take(agent: Agent, step: Step) -> Result(Agent, String) {
  let visited =
    [#(program_text(agent), step.action), ..agent.visited]
    |> list.take(remembered_states)
  let agent = Agent(..agent, visited:)
  let Agent(buffer:, environment:, config:, history:, ..) = agent
  // A function written where a function is expected, as the function given to
  // `map`, is finished rather than about to be called.
  let fills_function = case buffer.projection {
    #(p.Exp(e.Vacant), _) ->
      case buffer.target_type(buffer) {
        Ok(t.Fun(..)) -> True
        _ -> False
      }
    _ -> False
  }
  use buffer <- result.try(
    a.perform(step.action, buffer, environment, config.advance)
    |> result.replace_error("cannot " <> a.key(step.action) <> " here"),
  )
  // Code does the navigation when Jev is only asked to fill holes.
  // A function or record stays selected so it can be called or selected from.
  let buffer = case config.focus_holes, buffer.projection {
    True, #(p.Exp(e.Vacant), _) | False, _ -> buffer
    True, _ ->
      case buffer.target_type(buffer), fills_function {
        Ok(t.Fun(..)), False
        | Ok(t.Record(_)), _
        | Ok(t.Var(_)), _
        | Error(Nil), _
        -> buffer
        _, _ -> buffer.next_vacant(buffer) |> result.unwrap(buffer)
      }
  }
  // With no holes left the whole program is selected, so that a program giving
  // the wrong answer can be passed on or replaced rather than edited in part.
  // A function or record stays selected, it is about to be called or selected from.
  let buffer = case config.focus_holes && !a.is_navigation(step.action) {
    True ->
      case a.holes(buffer), buffer.target_type(buffer), fills_function {
        _, Ok(t.Fun(..)), False | _, Ok(t.Record(_)), _ -> buffer
        [], _, _ ->
          buffer.update_position(buffer, p.all(p.rebuild(buffer.projection)))
        _, _, _ -> buffer
      }
    False -> buffer
  }
  let agent = Agent(..agent, buffer:, history: [step, ..history])
  case step.action {
    a.RunTests -> Ok(Agent(..agent, test_results: Some(test_results(agent))))
    a.Finish -> Ok(Agent(..agent, finished: True))
    a.OpenLibrary(name) -> {
      let open_libraries = list.append(config.open_libraries, [name])
      Ok(Agent(..agent, config: options.Config(..config, open_libraries:)))
    }
    _ -> Ok(agent)
  }
}

pub fn test_results(agent: Agent) -> String {
  case run.tests(buffer.source(agent.buffer), agent.environment) {
    Ok(outcomes) -> run.summary(outcomes)
    Error(reason) -> "tests could not run: " <> reason
  }
}

/// A step for an action chosen without asking Jev, for example in a replay.
pub fn scripted(action) -> Step {
  Step(
    action:,
    confidence: 1.0,
    ranked: [#(a.key(action), 1.0)],
    offered: 0,
    input_tokens: 0,
    thinking_ms: 0,
    failed: False,
    label: a.key(action),
  )
}

pub fn type_error_count(agent: Agent) -> Int {
  list.length(a.type_errors(agent.buffer))
}

pub fn is_complete(agent: Agent) -> Bool {
  !string.contains(text.print(source(agent)), "?")
  && infer.all_errors(agent.buffer.analysis) == []
}

pub fn poly_to_string(poly: binding.Poly) {
  environment.render_poly(poly)
}

pub fn step_to_json(step: Step) -> Json {
  let Step(
    action:,
    confidence:,
    ranked:,
    offered:,
    input_tokens:,
    thinking_ms:,
    failed:,
    label:,
  ) = step
  json.object([
    #("action", a.to_json(action)),
    #("label", json.string(label)),
    #("confidence", json.float(confidence)),
    #(
      "ranked",
      json.array(ranked, fn(entry) {
        json.preprocessed_array([json.string(entry.0), json.float(entry.1)])
      }),
    ),
    #("offered", json.int(offered)),
    #("input_tokens", json.int(input_tokens)),
    #("thinking_ms", json.int(thinking_ms)),
    #("failed", json.bool(failed)),
  ])
}

pub fn step_decoder() -> decode.Decoder(Step) {
  let number =
    decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
  use action <- decode.field("action", a.decoder())
  use label <- decode.field("label", decode.string)
  use confidence <- decode.field("confidence", number)
  use ranked <- decode.field(
    "ranked",
    decode.list({
      use name <- decode.field(0, decode.string)
      use probability <- decode.field(1, number)
      decode.success(#(name, probability))
    }),
  )
  use offered <- decode.field("offered", decode.int)
  use input_tokens <- decode.field("input_tokens", decode.int)
  use thinking_ms <- decode.field("thinking_ms", decode.int)
  use failed <- decode.field("failed", decode.bool)
  decode.success(Step(
    action:,
    confidence:,
    ranked:,
    offered:,
    input_tokens:,
    thinking_ms:,
    failed:,
    label:,
  ))
}

// Each call in the program that performs effects, as `context.records("a")
// performs DNSimple`, in reading order.
fn effect_nodes(buffer: Buffer) -> List(String) {
  calls(p.rebuild(buffer.projection), [], [])
  |> list.reverse
  |> list.filter_map(fn(call) {
    let #(exp, path) = call
    case effects_at(buffer, path) {
      [] -> Error(Nil)
      labels -> Ok(short(exp) <> " performs " <> string.join(labels, ", "))
    }
  })
}

// Every call with its path, as `projection.path` gives it, outermost first.
fn calls(exp, path, found) {
  let child = fn(found, exp, index) {
    calls(exp, list.append(path, index), found)
  }
  case exp {
    e.Call(func, args) -> {
      let found = child([#(exp, path), ..found], func, [0])
      list.index_fold(args, found, fn(found, arg, i) {
        child(found, arg, [i + 1])
      })
    }
    e.Select(value, _) -> child(found, value, [0])
    e.Function(params, body) -> child(found, body, [list.length(params)])
    e.Block(assigns, then, _) -> {
      let found =
        list.index_fold(assigns, found, fn(found, assign, i) {
          child(found, assign.1, [i, 1])
        })
      child(found, then, [list.length(assigns)])
    }
    e.List(items, _) ->
      list.index_fold(items, found, fn(found, item, i) {
        child(found, item, [i])
      })
    e.Record(fields, _) ->
      list.index_fold(fields, found, fn(found, field, i) {
        child(found, field.1, [i * 2 + 1])
      })
    e.Case(top, _, _) -> child(found, top, [0])
    _ -> found
  }
}

fn effects_at(buffer: Buffer, path) -> List(String) {
  case infer.effect_at(buffer.analysis, list.reverse(path)) {
    Ok(effect) -> environment.effect_labels(effect) |> list.unique
    Error(Nil) -> []
  }
}

fn short(exp) {
  let code = text.print(exp) |> string.replace("\n", " ")
  case string.length(code) > 60 {
    True -> string.slice(code, 0, 57) <> "..."
    False -> code
  }
}
