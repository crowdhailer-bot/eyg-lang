import castor
import eyg/analysis/type_/binding/debug as t_debug
import eyg/hub/cache
import eyg/interpreter/state as istate
import eyg/parser/parser as _
import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import midas/continuation
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/web/environment.{type Environment}
import overlay/web/provider_setup
import overlay/web/tools
import pal/system

pub type Config(host) {
  Config(origin: origin.Origin, environment: Environment(host))
}

// The system prompt and tools are not part of the state as they are built from readme and always one tool
pub type State(host) {
  State(
    llm: provider.Llm,
    provider_setup: provider_setup.State,
    status: AgentStatus,
    history: List(chat.Message(tool.Call)),
    input: String,
    input_error: Option(String),
    origin: origin.Origin,
    environment: Environment(host),
    cache: cache.Cache(tools.Meta),
    counter: Int,
    expanded: set.Set(Int),
  )
}

pub type AgentStatus {
  Waiting
  Asking(messages: List(chat.Message(tool.Call)))
  Streaming(
    reader: system.Reader,
    completion: chat.Completion(tool.Call),
    remaining: BitArray,
  )
  Executing(calls: List(#(String, tools.Call)))
}

pub fn new(config: Config(host)) -> State(host) {
  let Config(origin:, environment:) = config
  let llm =
    provider.Llm(
      provider: provider.Ollama(ollama.Config(origin:, api_key: None)),
      model: "",
    )
  let cache = cache.ready()
  State(
    llm:,
    provider_setup: provider_setup.new(),
    status: Waiting,
    history: [],
    input: "",
    input_error: None,
    origin: origin,
    environment:,
    cache:,
    counter: 0,
    expanded: set.new(),
  )
}

pub fn init(config) {
  let state = new(config)
  let #(_, provider_effects) = provider_setup.init()
  let #(state, effects) = flush(state)
  let provider_effects =
    list.map(provider_effects, system.map(_, ProviderSetupMessage))
  #(state, list.append(provider_effects, effects))
}

pub type Effect(t) {
  Browser(system.Effect(Message))
  Done(t)
}

fn flush(state: State(host)) {
  let State(cache:, ..) = state
  let #(cache, effects) = cache.flush(cache)
  let effects =
    list.map(effects, fn(effect) {
      {
        use message <- continuation.then(cache.compute(
          effect,
          state.origin,
          system.fetch,
        ))
        continuation.return(CacheMessage(message))
      }(system.Done)
    })
  #(State(..state, cache:), effects)
}

pub type Message {
  ProviderSetupMessage(provider_setup.Message)
  UserUpdatedInput(String)
  UserSubmittedPrompt
  LlmStartedStreaming(reader: system.Reader)
  LlmStreamedCompletion(
    completions: List(chat.Completion(tool.Call)),
    remaining: BitArray,
  )
  LlmStreamFinished(Result(Nil, String))
  UserClickedExpand(Int)
  UserClickedShrink(Int)
  // run messages
  EffectHandled(task_id: Int, value: istate.Value(tools.Meta))
  CacheMessage(cache.ActionCompleted)
  Ignore
}

pub fn update(
  state: State(host),
  message: Message,
) -> #(State(host), List(system.Effect(Message))) {
  case message {
    ProviderSetupMessage(message) -> {
      let can_save = case state.status {
        Waiting -> True
        _ -> False
      }
      let #(setup, actions, llm) =
        provider_setup.update(
          state.provider_setup,
          message,
          state.origin,
          can_save,
        )
      let state = State(..state, provider_setup: setup)
      let state = case llm {
        Some(llm) -> State(..state, llm:)
        None -> state
      }
      let actions = list.map(actions, system.map(_, ProviderSetupMessage))
      #(state, actions)
    }
    UserUpdatedInput(input) -> {
      let state = State(..state, input:)
      #(state, [])
    }
    UserSubmittedPrompt ->
      case state.provider_setup.configured, state.status {
        False, _ -> {
          let provider_setup =
            provider_setup.require_configuration(state.provider_setup)
          #(State(..state, provider_setup:), [])
        }
        True, Waiting -> {
          case string.trim(state.input) {
            "" -> #(State(..state, input_error: Some("")), [])
            input -> {
              let message = chat.UserMessage(text: input, images: [])
              let action = fetch_completion(state, [message])
              let state = State(..state, status: Asking([message]), input: "")
              #(state, [action])
            }
          }
        }
        True, _ -> {
          let state =
            State(..state, input_error: Some("Cant send another message"))
          #(state, [])
        }
      }
    LlmStartedStreaming(reader) -> {
      case state.status {
        Asking(messages) -> {
          let history = list.append(messages, state.history)

          let state =
            State(
              ..state,
              status: Streaming(reader, chat.fresh(), <<>>),
              history:,
            )
          let action = stream_next_chunk(state.llm.provider, reader, <<>>)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamedCompletion(new, remaining) -> {
      case state.status {
        Streaming(reader:, completion:, remaining: _) -> {
          let completion = chat.append_chunks(completion, new)
          let state =
            State(..state, status: Streaming(reader:, completion:, remaining:))
          let action = stream_next_chunk(state.llm.provider, reader, remaining)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Ok(Nil)) -> {
      case state.status {
        Streaming(reader: _, completion:, remaining: _) -> {
          let message = chat.from_completion(completion)
          let history = [message, ..state.history]

          let state = State(..state, history:)
          case completion.tool_calls {
            [] -> #(State(..state, status: Waiting), [])
            calls -> {
              current_context(state)
              |> tools.execute_all(calls)
              |> resolve_calls(state)
            }
          }
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Error(reason)) -> {
      let state = State(..state, status: Waiting, input_error: Some(reason))
      #(state, [])
    }
    UserClickedExpand(index) -> {
      let expanded = set.insert(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    UserClickedShrink(index) -> {
      let expanded = set.delete(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    EffectHandled(task_id:, value:) -> {
      case state.status {
        // executing is always a non empty list
        Executing(calls) -> {
          current_context(state)
          |> tools.effect_handled(calls, task_id, value)
          |> resolve_calls(state)
        }
        _ -> #(state, [])
      }
    }
    CacheMessage(message) -> {
      let #(cache, _done) = cache.update(state.cache, message, fn(_) { [] })
      let state = State(..state, cache: cache)

      case state.status {
        Executing(calls) -> {
          let ctx = current_context(state)
          // multiple id's might be needed
          list.map_fold(calls, ctx, tools.restart)
          |> resolve_calls(state)
        }
        _ -> flush(state)
      }
    }

    Ignore -> #(state, [])
  }
}

pub fn can_save_provider(state: State(host)) {
  case state.provider_setup.restoring, state.status {
    False, Waiting -> True
    _, _ -> False
  }
}

// cache state doesn't update during the eval but needs to resume later if everything fetched at the beginning

fn current_context(state: State(host)) {
  workspace(state)
}

/// The workspace as it stands: the environment, the modules already fetched
/// and the next task number.
///
/// An application embedding overlay usually has another way to run a program
/// as well — a shell, a button — and those runs share the environment, the
/// cache and the numbering with the agent's. Take the workspace, run in it,
/// and put back what it became.
pub fn workspace(state: State(host)) -> tools.Context(host) {
  let State(environment:, cache:, counter:, ..) = state
  tools.Context(environment:, cache:, counter:, effects: [])
}

/// Put back a workspace something else has finished running in.
pub fn restore(state: State(host), ctx: tools.Context(host)) -> State(host) {
  let tools.Context(environment:, cache:, counter:, effects: _) = ctx
  State(..state, environment:, cache:, counter:)
}

fn resolve_calls(return, state: State(host)) {
  let #(ctx, calls) = return

  let tools.Context(environment:, cache:, counter:, effects: inner) = ctx
  let effects =
    list.map(
      inner,
      system.map(_, fn(return) {
        let #(id, value) = return
        EffectHandled(task_id: id, value:)
      }),
    )

  let #(status, effects) = case tools.all_returns(calls) {
    Error(Nil) -> #(Executing(calls), effects)
    Ok(messages) -> #(Asking(messages), [
      fetch_completion(state, messages),
      ..effects
    ])
  }

  let state = State(..state, status:, environment:, cache:, counter:)
  #(state, effects)
}

fn fetch_completion(state, messages) {
  use response <- system.FetchStreamResponse(completion_request(state, messages))

  case response {
    Ok(Response(200, body:, ..)) -> LlmStartedStreaming(body)
    Ok(Response(status: 401, body: _, ..)) ->
      LlmStreamFinished(Error("Provider rejected the API token (401)."))
    Ok(Response(status:, body: _, ..)) ->
      LlmStreamFinished(Error(
        "Provider returned HTTP " <> int.to_string(status) <> ".",
      ))
    Error(reason) -> LlmStreamFinished(Error(string.inspect(reason)))
  }
  |> system.Done
}

fn stream_next_chunk(provider, reader, remaining) {
  use chunk <- system.ReadChunk(reader)
  case chunk {
    Ok(Some(chunk)) -> {
      let #(completions, remaining) =
        provider.completion_chunk_parse(provider, remaining, chunk)
      LlmStreamedCompletion(completions, remaining)
    }
    Ok(None) -> LlmStreamFinished(Ok(Nil))
    Error(reason) -> LlmStreamFinished(Error(string.inspect(reason)))
  }
  |> system.Done
}

fn completion_request(
  state: State(host),
  messages: List(chat.Message(tool.Call)),
) {
  let tools = [spec()]
  let context =
    provider.Context(system_prompt: system_prompt(state.environment), tools:)
  let history = list.append(messages, state.history) |> list.reverse
  provider.stream_completion_request(state.llm, context, history)
}

/// What the model is told before the conversation starts.
///
/// The first half is true of overlay wherever it runs. The rest is the
/// environment: its briefing, then the effects it offers, written out with
/// their types. Nothing here knows what those effects are.
pub fn system_prompt(environment: Environment(host)) -> String {
  let environment.Environment(briefing:, effects:, ..) = environment

  "You are an expery automation assistant.
You help users by executing EYG scripts to interact with the users system.
DO NOT guess any function of effects. Only use what you have seen explained and use guide to learn more about writing EYG code.

ALWAYS use djot syntax for your responses.
DO NOT write code blocks in your responses unless explicitly asked.
All code execution uses the 'run' tool.

" <> briefing <> "

This environment has the following effects

"
  |> string.append(
    effects
    |> list.map(fn(effect) {
      let #(name, #(lift_type, lower_type)) = effect

      "- "
      <> name
      <> "("
      <> t_debug.mono(lift_type)
      <> ") -> "
      <> t_debug.mono(lower_type)
    })
    |> string.join("\n"),
  ) <> "

Remember to always use perform to call an effect."
}

pub fn spec() {
  let name = "run"

  let description =
    "Run an EYG program, the program may have effects at a top level."
  let parameters = [castor.field("code", castor.string())]
  tool.Tool(name, description, parameters)
}
