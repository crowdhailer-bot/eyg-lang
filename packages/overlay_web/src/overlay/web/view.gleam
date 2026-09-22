//// ViewModel for the core state

import eyg/hub/cache
import eyg/ir/tree as ir
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import jev_playground/agent
import overlay/llm/chat
import overlay/web/context
import overlay/web/jev_session
import overlay/web/state.{type State, State}

pub type Context {
  Default
  Loading(name: String)
  Loaded(name: String, has_readme: Bool)
  Failed(name: String, reason: String)
}

pub fn context(state: State) -> Context {
  let State(context_source:, context:, ..) = state
  let name = context.describe(context_source)
  case context_source, context {
    context.Default, _ -> Default
    _, context.Pulling(..) | _, context.Fetching(..) -> Loading(name)
    _, context.Loaded(..) ->
      Loaded(name, option.is_some(context.provided_readme(context)))
    _, context.Errored(reason:) -> Failed(name, reason)
  }
}

pub fn messages(state: State) {
  let State(status:, history:, ..) = state
  let messages = case status {
    state.Waiting -> history
    state.Asking(messages:) -> list.append(messages, state.history)
    state.Streaming(reader: _, completion:, remaining: _) -> {
      let chat.Completion(thinking:, content:, tool_calls:) = completion
      let message = chat.AssistantMessage(thinking:, text: content, tool_calls:)
      [message, ..history]
    }
    state.Executing(_calls) -> history
    state.Building(agent:, ..) -> [jev_progress(agent, "writing"), ..history]
    state.Answering(agent:, ..) -> [jev_progress(agent, "running"), ..history]
  }
  let length = list.length(messages)
  list.index_map(messages, fn(message, i) { #(length - i, message) })
}

pub type Waiting {
  PullingReleases
  Fetching(reference: String)
  Blocked(reference: String, on: String)
}

pub fn waiting_on(state: State) -> List(Waiting) {
  let State(cache:, ..) = state
  let cache.Cache(fetching_modules:, cursor_status:, ..) = cache

  let pulling = case cursor_status {
    cache.ReadyToPull | cache.Pulling -> [PullingReleases]
    cache.Pulled | cache.PullFailed(_) -> []
  }

  let #(fetching, blocked) =
    dict.fold(fetching_modules, #([], []), fn(acc, cid, status) {
      let #(fetching, blocked) = acc
      let reference = ir.reference_to_string(ir.Content(cid:))
      case status {
        cache.NotRequested | cache.Requested -> #(
          [Fetching(reference:), ..fetching],
          blocked,
        )
        cache.DependsOn(dep:, ..) -> #(fetching, [
          Blocked(
            reference:,
            on: ir.reference_to_string(cache.dep_to_reference(dep)),
          ),
          ..blocked
        ])
        // Neither is outstanding. A module the hub could not answer for, or
        // answered badly, is given to the agent as a missing reference.
        cache.Failed(_) | cache.Invalid(_) -> acc
      }
    })

  list.flatten([pulling, sorted(fetching), sorted(blocked)])
}

/// The statuses are held in a dict, which has an order of its own that can
/// change as it grows. Sorting keeps the list steady across renders.
fn sorted(waiting: List(Waiting)) -> List(Waiting) {
  use a, b <- list.sort(waiting)
  string.compare(order_string(a), order_string(b))
}

fn order_string(waiting: Waiting) -> String {
  case waiting {
    PullingReleases -> ""
    Fetching(reference:) -> reference
    Blocked(reference:, on: _) -> reference
  }
}

// While Jev works the program so far is shown with the selection marked and
// the last edit it chose.
fn jev_progress(agent: agent.Agent, doing: String) {
  let edits = list.length(agent.history)
  let last = case agent.history {
    [step, ..] ->
      "\n\nLast edit: "
      <> step.label
      <> " ("
      <> float.to_string(float.to_precision(step.confidence, 2))
      <> ")"
    [] -> ""
  }
  let text =
    "Jev is "
    <> doing
    <> " the program, "
    <> int.to_string(edits)
    <> " edits so far\n\n```eyg\n"
    <> agent.program_text(agent)
    <> "\n```"
    <> last
    <> case edits {
      0 -> ""
      _ -> "\n\n```edits\n" <> jev_session.edits(agent) <> "\n```"
    }
  chat.AssistantMessage(thinking: "", text:, tool_calls: [])
}
