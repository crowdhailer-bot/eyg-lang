import eyg/cli/args
import eyg/cli/internal/config
import eyg/cli/overlay as cli
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import loam/execute
import loam/system
import oas/generator/utils
import overlay/agent
import overlay/llm/chat
import overlay/llm/tool
import terminal/cell
import terminal/driver
import terminal/protocol as p

type State {
  State(
    session: cli.Session,
    runtime: execute.State,
    history: List(chat.Message(tool.Call)),
    sequence: Int,
  )
}

pub opaque type Runtime {
  Runtime(
    state: cell.Cell(State),
    id: cell.Cell(Int),
    io: driver.IO,
    emit: fn(p.Event) -> Nil,
  )
}

pub fn initialize(arguments, emit, prompt) {
  let id = cell.new(0)
  let io =
    driver.IO(
      output: fn(text, error) { emit(p.Output(cell.read(id), text, error)) },
      fetch: fn(url) { emit(p.Fetch(cell.read(id), url)) },
      prompt:,
    )
  let initial = {
    use settings <- system.then(config.load())
    use settings <- system.try(result.replace_error(
      settings,
      "Failed to load config",
    ))
    case args.parse(arguments) {
      args.Overlay(input) -> cli.initialize(input, settings)
      _ -> system.Done(Error("Expected an overlay config"))
    }
  }
  use initial <- promise.map(driver.drive(initial, io))
  use #(session, runtime) <- result.map(initial)
  emit(p.OverlayReady(session.llm.model))
  Runtime(cell.new(State(session, runtime, [], 0)), id, io, emit)
}

pub fn evaluate(runtime: Runtime, id, source) {
  let started = driver.now()
  cell.write(runtime.id, id)
  let state = cell.read(runtime.state)
  let export_path = case source {
    "/export" <> path ->
      case path == "" || string.trim_start(path) != path {
        True -> Ok(string.trim(path))
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
  let work = case export_path {
    Ok(path) ->
      driver.drive(cli.export(state.session, state.history, path), runtime.io)
      |> promise.map(fn(_) { Ok(Nil) })
    Error(_) -> {
      cell.write(
        runtime.state,
        State(..state, history: [chat.UserMessage(source, []), ..state.history]),
      )
      complete(runtime)
    }
  }
  use result <- promise.map(work)
  case result {
    Ok(Nil) -> runtime.emit(p.Complete(id, [], "", driver.now() -. started))
    Error(message) -> runtime.emit(p.Failure(id, message))
  }
}

fn complete(runtime: Runtime) -> promise.Promise(Result(Nil, String)) {
  let state = cell.read(runtime.state)
  let id = state.sequence - 1
  cell.write(runtime.id, id)
  cell.write(runtime.state, State(..state, sequence: id))
  let completion =
    cli.completion(state.session, list.reverse(state.history), fn(text) {
      case text {
        "" -> Nil
        _ -> runtime.emit(p.Assistant(id, text))
      }
      system.Done(Nil)
    })
  use completion <- promise.try_await(driver.drive(completion, runtime.io))
  let state = cell.read(runtime.state)
  cell.write(
    runtime.state,
    State(..state, history: [chat.from_completion(completion), ..state.history]),
  )
  case completion.tool_calls {
    [] -> promise.resolve(Ok(Nil))
    calls -> {
      use Nil <- promise.await(run_calls(runtime, calls))
      complete(runtime)
    }
  }
}

fn run_calls(runtime: Runtime, calls: List(tool.Call)) -> promise.Promise(Nil) {
  case calls {
    [] -> promise.resolve(Nil)
    [call, ..rest] -> {
      let state = cell.read(runtime.state)
      let id = state.sequence - 1
      cell.write(runtime.id, id)
      cell.write(runtime.state, State(..state, sequence: id))
      let started = driver.now()
      let code = case
        agent.cast_tool_call(call.function.name, call.function.arguments)
      {
        Ok(agent.Run(code)) -> code
        _ -> utils.fields_to_json(call.function.arguments) |> json.to_string
      }
      runtime.emit(p.Tool(id, call.function.name, code))
      let effect =
        cli.call_observed(
          state.session,
          call.function,
          state.runtime,
          fn(label, input, decision, output) {
            runtime.emit(p.Effect(
              id,
              p.EffectRecord(label, input, output, Some(decision)),
            ))
          },
        )
      use #(returned, next) <- promise.await(driver.drive(effect, runtime.io))
      let state = cell.read(runtime.state)
      cell.write(
        runtime.state,
        State(..state, runtime: next, history: [
          cli.result_to_message(call.id, returned),
          ..state.history
        ]),
      )
      let #(text, error) = case returned {
        Ok(returned) -> #(returned.text, False)
        Error(message) -> #(message, True)
      }
      runtime.emit(p.ToolResult(id, text, error, driver.now() -. started))
      run_calls(runtime, rest)
    }
  }
}
