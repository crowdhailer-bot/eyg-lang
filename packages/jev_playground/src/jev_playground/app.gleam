//// The playground web page: a task, the program Jev is building and a loop
//// that keeps asking Jev for the next edit.
//// `/` runs live against the API through the dev server proxy,
//// `/demo/<slug>` replays a demo with mocked answers.

import gleam/dict
import gleam/dynamic/decode
import gleam/fetch
import gleam/float
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import jev
import jev_playground/action.{type Action}
import jev_playground/agent
import jev_playground/client
import jev_playground/demo
import jev_playground/environment
import jev_playground/eval
import jev_playground/library
import jev_playground/mock
import jev_playground/options
import lustre/effect.{type Effect}
import morph/editable as e
import ogre/origin
import plinth/browser/document
import plinth/browser/dom_rect
import plinth/browser/element
import plinth/browser/location
import plinth/browser/window
import plinth/javascript/global

pub type Source {
  Live(transport: client.Transport, model: String)
  Replay(demo: demo.Demo, actions: List(Action), speed: Float)
  /// A saved eval run, replayed at the speed Jev answered.
  Recorded(name: String, run: Option(eval.Run), speed: Float)
}

pub type Status {
  Loading
  Idle
  Thinking(started: Float)
  Waiting
  Paused
  Finished
  Failed(reason: String)
}

/// A choice shown in the list of recent selections.
pub type Selection {
  Selection(id: Int, name: String, step: agent.Step)
}

pub type Model {
  Model(
    source: Source,
    task: String,
    environment: environment.Environment,
    agent: agent.Agent,
    status: Status,
    running: Bool,
    generation: Int,
    offered: List(options.Option),
    selections: List(Selection),
    now: Float,
    tokens: Int,
  )
}

pub type Message {
  UserEditedTask(String)
  UserClickedRun
  UserClickedPause
  UserClickedStep
  UserClickedReset
  JevAnswered(generation: Int, result: Result(#(jev.Evaluation, Int), String))
  Continue(generation: Int)
  Ticked(Float)
  LibrariesLoaded(
    Result(#(library.Bundle, dict.Dict(String, demo.Prepared)), String),
  )
  RunLoaded(Result(eval.Run, String))
  Replayed(generation: Int, step: agent.Step)
}

/// The number of recent selections shown, one more is kept while it fades out.
pub const shown = 8

const max_steps = 600

const pause_ms = 260

pub fn location_flags() {
  let location = window.location(window.self())
  let query = location.search(location) |> result.unwrap("")
  #(location.pathname(location), query, location.origin(location))
}

/// Libraries are loaded before anything starts, demos are then scripted
/// against the same environment they are replayed in.
pub fn init(flags: #(String, String, String)) -> #(Model, Effect(Message)) {
  let #(path, query, origin) = flags
  let query =
    uri.parse_query(string.remove_prefix(query, "?")) |> result.unwrap([])
  let #(source, task, running) = case string.split(path, "/") {
    ["", "demo", slug, ..] ->
      case demo.find(slug) {
        Ok(demo) -> {
          #(
            Ok(Replay(demo:, actions: [], speed: speed(query))),
            demo.task,
            True,
          )
        }
        Error(Nil) -> #(Error("no demo " <> slug), "", False)
      }
    ["", "eval", name] -> #(
      Ok(Recorded(name:, run: None, speed: speed(query))),
      "",
      True,
    )
    // `?task=..` starts Jev on the task straight away, for sharing and recording runs.
    _ ->
      case list.key_find(query, "task") {
        Ok(task) -> #(Ok(live(origin)), task, True)
        Error(Nil) -> #(Ok(live(origin)), "", False)
      }
  }
  case source {
    Ok(source) -> {
      let model = new(source, task, base(source))
      #(Model(..model, status: Loading, running:), load_libraries(origin))
    }
    Error(reason) -> {
      let model = new(live(origin), "", environment.browser())
      #(Model(..model, status: Failed(reason)), effect.none())
    }
  }
}

fn speed(query) {
  list.key_find(query, "speed")
  |> result.try(fn(speed) {
    // `float.parse` needs a decimal point, `?speed=2` is written as a whole number.
    result.lazy_or(float.parse(speed), fn() {
      int.parse(speed) |> result.map(int.to_float)
    })
  })
  |> result.unwrap(1.0)
}

fn live(origin) {
  let assert Ok(origin) = origin.from_string(origin)
  Live(transport: client.Proxy(origin), model: jev.latest)
}

fn base(source) {
  case source {
    Replay(demo:, ..) -> demo.environment
    Recorded(..) -> environment.pure()
    Live(..) -> environment.browser()
  }
}

fn new(source, task, environment) {
  let config = case source {
    Replay(demo:, ..) -> demo.config
    Recorded(run: Some(run), ..) -> eval.config(run.eval, run.variant)
    Recorded(run: None, ..) -> options.default_config()
    Live(..) ->
      options.Config(..options.default_config(), search_libraries: True)
  }
  Model(
    source:,
    task:,
    environment:,
    agent: agent.new(task, e.Vacant, environment, config),
    status: Idle,
    running: False,
    generation: 0,
    offered: [],
    selections: [],
    now: client.now(),
    tokens: 0,
  )
}

// Demo scripts are found when the page is built, a page can find them itself if missing.
fn load_libraries(origin) {
  effect.from(fn(dispatch) {
    {
      use libraries <- promise.await(get_json(
        origin <> "/libraries.json",
        library.decoder(),
      ))
      use demos <- promise.map(get_json(
        origin <> "/demos.json",
        decode.dict(decode.string, demo.prepared_decoder()),
      ))
      let demos = result.unwrap(demos, dict.new())
      dispatch(LibrariesLoaded(result.map(libraries, fn(b) { #(b, demos) })))
    }
    Nil
  })
}

fn get_json(url, decoder) {
  let assert Ok(request) = request.to(url)
  use response <- promise.map(
    fetch.send(request) |> promise.try_await(fetch.read_text_body),
  )
  case response {
    Ok(response) ->
      json.parse(response.body, decoder)
      |> result.replace_error("could not decode " <> url)
    Error(reason) -> Error(string.inspect(reason))
  }
}

fn loaded(model: Model, result) {
  let setup = {
    use #(bundle, demos) <- result.try(result)
    use environment <- result.try(library.environment(
      bundle,
      base(model.source),
    ))
    use #(source, task) <- result.map(case model.source {
      Replay(demo:, speed:, ..) -> {
        use prepared <- result.map(case dict.get(demos, demo.slug) {
          Ok(prepared) -> Ok(prepared)
          Error(Nil) -> demo.prepare(demo, environment)
        })
        #(Replay(demo:, actions: prepared.actions, speed:), prepared.task)
      }
      live -> Ok(#(live, model.task))
    })
    #(source, task, environment)
  }
  case setup {
    Ok(#(source, task, environment)) -> {
      let fresh = new(source, task, environment)
      let model = Model(..fresh, running: model.running)
      case source, model.running {
        // A recorded run is loaded once the environment it ran in is ready.
        Recorded(name:, run: None, ..), _ -> #(
          Model(..model, status: Loading),
          load_run(origin_of(), name),
        )
        // Pause on the empty program so a recording shows the start.
        _, True -> #(model, delay(1500, Continue(model.generation)))
        _, False -> #(model, effect.none())
      }
    }
    Error(reason) -> #(
      Model(..model, status: Failed(reason), running: False),
      effect.none(),
    )
  }
}

pub fn update(model: Model, message) -> #(Model, Effect(Message)) {
  case message {
    UserEditedTask(task) -> {
      let agent = agent.with_task(model.agent, task)
      #(Model(..model, task:, agent:), effect.none())
    }
    UserClickedRun -> {
      let model = Model(..model, running: True)
      case model.status {
        Idle | Paused -> ask(model)
        _ -> #(model, effect.none())
      }
    }
    UserClickedPause -> #(Model(..model, running: False), effect.none())
    UserClickedStep ->
      case model.status {
        Idle | Paused -> ask(Model(..model, running: False))
        _ -> #(model, effect.none())
      }
    UserClickedReset -> {
      let fresh = new(model.source, model.task, model.environment)
      #(Model(..fresh, generation: model.generation + 1), effect.none())
    }
    Continue(generation) if generation == model.generation ->
      case model.running, model.status {
        True, Idle | True, Waiting -> ask(model)
        _, Waiting -> #(Model(..model, status: Paused), effect.none())
        _, _ -> #(model, effect.none())
      }
    Continue(_) -> #(model, effect.none())
    JevAnswered(generation, result) if generation == model.generation ->
      answered(model, result)
    JevAnswered(..) -> #(model, effect.none())
    LibrariesLoaded(result) -> loaded(model, result)
    RunLoaded(Ok(run)) ->
      case model.source {
        Recorded(name:, speed:, ..) -> {
          let source = Recorded(name:, run: Some(run), speed:)
          let start = eval.start(run.eval) |> result.unwrap(e.Vacant)
          let agent =
            agent.new(
              run.eval.task,
              start,
              model.environment,
              eval.config(run.eval, run.variant),
            )
          let model =
            Model(..model, source:, task: run.eval.task, agent:, status: Idle)
          #(model, delay(1500, Continue(model.generation)))
        }
        _ -> #(model, effect.none())
      }
    RunLoaded(Error(reason)) -> #(
      Model(..model, status: Failed(reason), running: False),
      effect.none(),
    )
    Replayed(generation, step) if generation == model.generation ->
      replayed(model, step)
    Replayed(..) -> #(model, effect.none())
    Ticked(now) ->
      case model.status {
        Thinking(..) -> #(Model(..model, now:), tick())
        _ -> #(Model(..model, now:), effect.none())
      }
  }
}

fn ask(model: Model) {
  let steps = list.length(model.agent.history)
  case model.agent.finished || steps >= max_steps {
    True -> #(Model(..model, status: Finished, running: False), effect.none())
    False -> {
      let now = client.now()
      let #(request_effect, offered) = request(model)
      let model = Model(..model, status: Thinking(started: now), now:, offered:)
      #(model, effect.batch([request_effect, tick()]))
    }
  }
}

fn request(model: Model) {
  let generation = model.generation
  case model.source {
    Live(transport:, model: jev_model) -> {
      let #(request, offered) = agent.request(model.agent, jev_model)
      let effect =
        effect.from(fn(dispatch) {
          client.system_one(transport, request)
          |> promise.map(fn(reply) {
            let result =
              result.map(reply, fn(reply) {
                #(reply.evaluation, reply.thinking_ms)
              })
            dispatch(JevAnswered(generation, result))
          })
          Nil
        })
      #(effect, offered)
    }
    Recorded(run: Some(run), speed:, ..) -> {
      let offered = agent.options(model.agent)
      let step = list.length(model.agent.history)
      let effect = case list.drop(run.steps, step) |> list.first {
        Ok(recorded) ->
          delay(
            float.round(int.to_float(recorded.thinking_ms) /. speed),
            Replayed(generation, recorded),
          )
        Error(Nil) ->
          dispatch(JevAnswered(generation, Error("the run " <> run.outcome)))
      }
      #(effect, offered)
    }
    Recorded(run: None, ..) -> #(effect.none(), [])
    Replay(actions:, speed:, ..) -> {
      let offered = agent.options(model.agent)
      let step = list.length(model.agent.history)
      let effect = case list.drop(actions, step) |> list.first {
        Ok(action) ->
          case
            mock.answer(offered, agent.candidates(model.agent, _), action, step)
          {
            Ok(#(evaluation, thinking_ms)) ->
              delay(
                float.round(int.to_float(thinking_ms) /. speed),
                JevAnswered(generation, Ok(#(evaluation, thinking_ms))),
              )
            Error(reason) -> dispatch(JevAnswered(generation, Error(reason)))
          }
        Error(Nil) ->
          dispatch(JevAnswered(generation, Error("the demo script has ended")))
      }
      #(effect, offered)
    }
  }
}

fn answered(model: Model, result) {
  case result {
    Error(reason) -> #(
      Model(..model, status: Failed(reason), running: False),
      effect.none(),
    )
    Ok(#(evaluation, thinking_ms)) ->
      case agent.answer(model.agent, model.offered, evaluation, thinking_ms) {
        Error(reason) -> #(
          Model(..model, status: Failed(reason), running: False),
          effect.none(),
        )
        Ok(agent) -> applied(model, agent)
      }
  }
}

// Replay a step saved from an eval run, checking the program as the run did.
fn replayed(model: Model, step: agent.Step) {
  let agent = case agent.take(model.agent, step) {
    Ok(agent) -> agent
    Error(_) ->
      agent.Agent(..model.agent, history: [
        agent.Step(..step, failed: True),
        ..model.agent.history
      ])
  }
  let agent = case model.source {
    Recorded(run: Some(run), ..) -> {
      let #(agent, solved) = eval.after_step(run.eval, agent, step)
      agent.Agent(..agent, finished: agent.finished || solved)
    }
    _ -> agent
  }
  applied(model, agent)
}

fn applied(model: Model, agent: agent.Agent) {
  case agent.history {
    [] -> #(model, effect.none())
    [step, ..] -> {
      let id = list.length(agent.history)
      let name = step.label
      let selections =
        [Selection(id:, name:, step:), ..model.selections]
        |> list.take(shown + 1)
      let tokens = model.tokens + step.input_tokens
      let model = Model(..model, agent:, selections:, tokens:)
      case agent.finished {
        True -> #(Model(..model, status: Finished, running: False), scroll())
        False -> {
          let pause = case model.source {
            Replay(speed:, ..) | Recorded(speed:, ..) ->
              float.round(int.to_float(pause_ms) /. speed)
            Live(..) -> pause_ms
          }
          #(
            Model(..model, status: Waiting),
            effect.batch([
              delay(pause, Continue(model.generation)),
              scroll(),
            ]),
          )
        }
      }
    }
  }
}

fn delay(ms, message) {
  effect.from(fn(dispatch) {
    global.set_timeout(ms, fn() { dispatch(message) })
    Nil
  })
}

fn dispatch(message) {
  effect.from(fn(dispatch) { dispatch(message) })
}

fn tick() {
  effect.from(fn(dispatch) {
    global.set_timeout(100, fn() { dispatch(Ticked(client.now())) })
    Nil
  })
}

fn scroll() {
  effect.after_paint(fn(_dispatch, _root) { scroll_to_selection() })
}

// Keep the selection in view by scrolling the program panel vertically only.
fn scroll_to_selection() -> Nil {
  let _ = {
    use selection <- result.try(document.query_selector(".code .selection"))
    use panel <- result.map(element.closest(selection, ".panel"))
    let scrolled = element.scroll_top(panel)
    let top =
      dom_rect.y(element.get_bounding_client_rect(selection))
      -. dom_rect.y(element.get_bounding_client_rect(panel))
      +. scrolled
    let height = int.to_float(element.client_height(panel))
    case top <. scrolled +. 40.0 || top >. scrolled +. height -. 60.0 {
      True -> {
        let target = float.max(0.0, top -. height /. 3.0)
        element.scroll_to(panel, target, element.scroll_left(panel), "smooth")
      }
      False -> Nil
    }
  }
  Nil
}

pub fn thinking_ms(model: Model) -> Option(Int) {
  case model.status {
    Thinking(started:) -> Some(float.round(model.now -. started))
    _ -> None
  }
}

fn load_run(origin, name) {
  effect.from(fn(dispatch) {
    get_json(origin <> "/evals/" <> name <> ".json", eval.run_decoder())
    |> promise.map(fn(result) { dispatch(RunLoaded(result)) })
    Nil
  })
}

fn origin_of() {
  location.origin(window.location(window.self()))
}
