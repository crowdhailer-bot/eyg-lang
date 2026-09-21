//// An agent is Jev editing a program towards a task, one choice at a time.
//// Each step builds a request describing the program and every available
//// edit, the chosen edit is then applied. No IO happens here.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import gleam/dict
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

const instructions = "Choose the single next edit that makes the most progress towards completing the task. The selected code is marked with « and » in `program`. Most edits replace or wrap the selection, `?` marks code still to be written."

const recent_actions = 6

pub fn new(task, source: e.Expression, environment, config) -> Agent {
  let buffer =
    buffer.from_projection(
      p.all(source),
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
  options.available(agent.buffer, agent.environment, vocabulary, agent.config)
  |> list.take(jev.max_choice_options)
}

pub fn program_text(agent: Agent) {
  text.projection(agent.buffer.projection, selection)
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
        #("program", json.string(program_text(agent))),
        #("selection", selection_json(buffer)),
        #("type_errors", json.array(errors, json.string)),
      ],
      case environment.effects {
        [] -> []
        _ -> [
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
        Some(results) -> [#("test_results", json.string(results))]
        None -> []
      },
      [#("recent_edits", json.preprocessed_array(recent))],
    ]),
  )
}

fn selection_json(buffer: Buffer) {
  let type_ = case buffer.target_type(buffer) {
    Ok(t.Var(_)) | Error(Nil) -> []
    Ok(type_) -> [#("type", json.string(environment.show_type(type_)))]
  }
  json.object([#("kind", json.string(options.focus_kind(buffer))), ..type_])
}

pub fn question(offered: List(options.Option)) -> jev.Question {
  let criteria =
    list.map(offered, fn(option) {
      #(options.key(option), Some(json.string(option.description)))
    })
  jev.Choice(json.string(instructions), criteria)
}

/// The candidates offered in the question for a slot.
pub fn candidates(agent: Agent, slot) -> List(String) {
  let vocabulary = vocabulary.with_task(agent.task_vocabulary, source(agent))
  options.candidates(slot, agent.buffer, vocabulary)
  |> list.filter(fn(text) { text != "" })
  |> list.unique
  |> list.take(jev.max_choice_options)
}

const slots = [options.NameSlot, options.LabelSlot]

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
  let request =
    jev.Request(model:, state: state(agent), questions: [
      #(question_id, question(offered)),
      ..slot_questions
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
        Ok(agent) -> Ok(agent)
        Error(_) -> {
          let step = Step(..step, failed: True)
          Ok(Agent(..agent, history: [step, ..agent.history]))
        }
      }
    }
    _ -> Error("expected a choice answer")
  }
}

/// Apply an action as the next step.
pub fn take(agent: Agent, step: Step) -> Result(Agent, String) {
  let Agent(buffer:, environment:, config:, history:, ..) = agent
  use buffer <- result.try(
    a.perform(step.action, buffer, environment, config.advance)
    |> result.replace_error("cannot " <> a.key(step.action) <> " here"),
  )
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
