//// `eyg tui`, the shell drawn with étui. The loop owns the terminal and the
//// shell: it advances the shell's work a slice at a time and polls for keys
//// in between, so the screen stays responsive while EYG runs. `tui/host` holds
//// what differs between targets.

import etui/backend
import etui/backend/default
import etui/geometry
import etui/terminal
import eyg/cli/internal/config
import eyg/cli/tui/agent.{type Agent}
import eyg/cli/tui/completion
import eyg/cli/tui/host
import eyg/cli/tui/model.{type Model}
import eyg/cli/tui/shell.{type Shell}
import eyg/cli/tui/structural
import eyg/cli/tui/view
import eyg/ir/tree
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string as text
import loam/execute
import loam/system
import overlay/llm/tool
import simplifile

/// Work the shell has been asked to do, returning to the loop when finished.
type Outcome {
  Started(Result(Shell, String))
  Evaluated(shell.Evaluated)
  AgentStarted(Result(Agent, String))
  Generated(Result(List(tool.Call), String), Agent)
  Called(Result(String, String), List(shell.Performed), Agent)
  Saved(Result(String, String))
  Exported
}

type Work {
  Idle
  Working(
    id: Int,
    started: Float,
    next: host.Pending(
      Result(#(List(shell.Event), shell.Progress(Outcome)), String),
    ),
  )
  Waiting(id: Int, started: Float, resume: fn(String) -> system.Effect(Outcome))
}

/// Work that changes the model when it finishes, such as finding packages.
type Task =
  host.Pending(fn(Model) -> #(Model, List(model.Command)))

type State(backend) {
  State(
    model: Model,
    work: Work,
    background: List(#(Int, Task)),
    tasks: Int,
    term: terminal.Terminal(backend),
    top: Option(Int),
    drawn: view.Drawn,
    quit: Bool,
  )
}

/// Milliseconds between frames, and of work between polls for input.
const frame = 16

/// `eyg tui`, the shell.
pub fn run(input) -> host.Pending(Nil) {
  open(False, fn(config) { system.map(shell.start(input, config), Started) })
}

/// `eyg tui overlay`, an Overlay agent.
pub fn overlay(input) -> host.Pending(Nil) {
  open(True, fn(config) { system.map(agent.start(input, config), AgentStarted) })
}

fn open(overlay, starting) -> host.Pending(Nil) {
  use loaded <- host.await(host.run(config.load()))
  use home <- host.await(host.run(system.env("HOME")))
  let home = result.unwrap(home, None)
  case loaded {
    Ok(Error(_)) | Error(_) -> {
      io.println_error("failed to load config")
      host.resolve(Nil)
    }
    Ok(Ok(config)) -> {
      let directory = simplifile.current_directory() |> result.unwrap(".")
      // The home directory is shown as ~, as a shell prompt does.
      let directory = case home {
        Some(home) if home != "" ->
          case text.split_once(directory, home) {
            Ok(#("", rest)) -> "~" <> rest
            _ -> directory
          }
        _ -> directory
      }
      let assert Ok(term) =
        terminal.new(
          default.new_with_options(backend.Options(mouse: True, paste: True)),
        )
      State(
        model: model.new(directory, overlay),
        work: Idle,
        background: [],
        tasks: 0,
        term:,
        top: None,
        drawn: view.empty(),
        quit: False,
      )
      |> start(0, starting(config))
      |> loop
    }
  }
}

fn loop(state: State(_)) -> host.Pending(Nil) {
  case state.quit {
    True -> {
      terminal.restore(state.term)
      host.resolve(Nil)
    }
    False -> {
      let state = draw(state)
      // Whatever settles first changes the state; keys are read in between.
      let pending =
        list.flatten([
          case state.work {
            Working(id:, started:, next:) -> [
              host.map(next, fn(progressed) {
                progress(_, id, started, progressed)
              }),
            ]
            Idle | Waiting(..) -> []
          },
          list.map(state.background, fn(task) {
            host.map(task.1, fn(update) { finish(_, task.0, update) })
          }),
        ])
      case pending {
        [] -> poll(state, frame)
        _ -> {
          use update <- host.await(
            host.first(pending, frame, fn(state) { state }),
          )
          poll(update(state), 0)
        }
      }
    }
  }
}

fn poll(state: State(_), timeout) {
  use polled <- host.await(terminal.poll(state.term, timeout))
  case polled {
    Ok(#(event, term)) -> loop(input(State(..state, term:), event))
    Error(_) -> loop(State(..state, quit: True))
  }
}

fn draw(state: State(_)) {
  case
    terminal.draw_with(state.term, fn(frame) {
      view.draw(frame, state.model, state.top)
    })
  {
    Ok(#(term, drawn)) -> State(..state, term:, drawn:)
    Error(_) -> state
  }
}

fn start(state: State(_), id, effect) {
  State(..state, work: Working(id, shell.now(), advance(effect)))
}

fn advance(effect) {
  host.advance(effect, int.to_float(frame))
}

fn progress(state: State(_), id, started, progressed) {
  case progressed {
    Error(message) -> failed(state, id, message)
    Ok(#(events, progress)) -> {
      let model =
        list.fold(events, state.model, fn(model, event) {
          model.received(model, id, event)
        })
      let state = State(..state, model:)
      case progress {
        shell.Paused(effect) ->
          State(..state, work: Working(id, started, advance(effect)))
        shell.Asking(prompt, resume) ->
          State(
            ..state,
            model: model.asked(state.model, prompt),
            work: Waiting(id, started, resume),
          )
        shell.Exited(status) ->
          failed(state, id, "Exited with status " <> int.to_string(status))
        shell.Finished(Started(Ok(shell))) ->
          State(..state, model: model.started(state.model, shell), work: Idle)
          |> spawn(discover(shell))
        shell.Finished(Started(Error(message))) -> failed(state, id, message)
        shell.Finished(AgentStarted(Ok(agent))) ->
          State(
            ..state,
            model: model.agent_started(state.model, agent),
            work: Idle,
          )
        shell.Finished(AgentStarted(Error(message))) ->
          failed(state, id, message)
        shell.Finished(Generated(result, agent)) ->
          State(..state, work: Idle)
          |> apply(model.generated(state.model, id, result, agent))
        shell.Finished(Called(result, performed, agent)) -> {
          let duration = shell.now() -. started
          State(..state, work: Idle)
          |> apply(model.called(
            state.model,
            id,
            result,
            performed,
            agent,
            duration,
          ))
        }
        shell.Finished(Saved(result)) ->
          State(..state, model: model.saved(state.model, result), work: Idle)
        shell.Finished(Exported) ->
          State(..state, work: Idle) |> apply(#(state.model, [model.Save(id)]))
        shell.Finished(Evaluated(evaluated)) -> {
          let duration = shell.now() -. started
          State(..state, work: Idle)
          |> apply(model.completed(state.model, id, evaluated, duration))
        }
      }
    }
  }
}

fn spawn(state: State(_), task) {
  let background = [#(state.tasks, task), ..state.background]
  State(..state, background:, tasks: state.tasks + 1)
}

fn finish(state: State(_), task, update) {
  let background = list.filter(state.background, fn(entry) { entry.0 != task })
  apply(State(..state, background:), update(state.model))
}

/// Published packages, found without holding up evaluation.
fn discover(shell: Shell) -> Task {
  use pulled <- host.map(host.run(execute.pull(shell.execution)))
  case pulled {
    Ok(execution) -> model.discovered(_, execution)
    Error(_) -> fn(model) { #(model, []) }
  }
}

/// The type of a referenced module, for structural editing.
fn load(reference, shell: Shell) -> Task {
  let failed = "Unable to load " <> tree.reference_to_string(reference)
  use loaded <- host.map(
    host.run(structural.load_reference(reference, shell.execution)),
  )
  let type_ = case loaded {
    Ok(#(Ok(type_), _)) -> Ok(type_)
    _ -> Error(failed)
  }
  model.loaded(_, reference, type_)
}

fn failed(state: State(_), id, message) {
  State(..state, model: model.failed(state.model, id, message), work: Idle)
}

fn input(state: State(_), event) {
  case event {
    backend.KeyPress(key) -> apply(state, model.key(state.model, key))
    backend.Paste(text) -> apply(state, model.paste(state.model, text))
    backend.MousePress(x, y, backend.MouseLeft) ->
      case
        list.find(state.drawn.clicks, fn(hit) {
          geometry.contains(hit.0, geometry.Position(x, y))
        })
      {
        Ok(#(_, click)) -> apply(state, model.click(state.model, click))
        Error(Nil) -> state
      }
    backend.MouseScroll(_, _, up) ->
      scroll(state, case up {
        True -> -3
        False -> 3
      })
    _ -> state
  }
}

fn apply(state: State(_), result) {
  let #(model, commands) = result
  list.fold(commands, State(..state, model:), perform)
}

fn perform(state: State(_), command) {
  case command {
    model.Evaluate(id, code) ->
      case state.model.shell, code {
        Some(current), model.Text(source) ->
          start(
            state,
            id,
            system.map(shell.evaluate(current, source), Evaluated),
          )
        Some(current), model.Ir(code) ->
          start(
            state,
            id,
            system.map(shell.evaluate_ir(current, code), Evaluated),
          )
        None, _ -> failed(state, id, "The shell has not started")
      }
    model.Answer(text) ->
      case state.work {
        Waiting(id:, started:, resume:) ->
          State(..state, work: Working(id, started, advance(resume(text))))
        _ -> state
      }
    model.Quit -> State(..state, quit: True)
    model.FollowTail -> State(..state, top: None)
    model.Reveal(anchor) ->
      case list.key_find(state.drawn.anchors, anchor) {
        Ok(row) -> State(..state, top: Some(row))
        Error(Nil) -> state
      }
    model.Scroll(delta) -> scroll(state, delta)
    model.Complete -> {
      let model = state.model
      let text = model.editor.text
      let choices = case model.input(model) {
        Some(model.Input(kind: model.FileInput, ..)) ->
          completion.files(text, text.length(text), ".")
        Some(model.Input(kind: model.PackageInput, ..)) ->
          list.map(model.packages, fn(name) { #(name, "hub package") })
          |> completion.hints(text, _)
        Some(model.Input(input:, ..)) ->
          completion.hints(text, structural.input_details(input).1)
        None ->
          completion.complete(text, model.editor.cursor, model.packages, ".")
      }
      State(..state, model: model.completed_choices(model, choices))
    }
    model.Copy(text) -> {
      io.print(osc52(text))
      state
    }
    model.Ask(id, text) ->
      with_agent(state, id, fn(agent) {
        use #(result, agent) <- system.map(agent.ask(agent, text))
        Generated(result, agent)
      })
    model.Generate(id) ->
      with_agent(state, id, fn(agent) {
        use #(result, agent) <- system.map(agent.generate(agent))
        Generated(result, agent)
      })
    model.Call(id, call, index) ->
      with_agent(state, id, fn(agent) {
        use #(result, performed, agent) <- system.map(agent.call(
          agent,
          call,
          index,
        ))
        Called(result, performed, agent)
      })
    model.Save(id) ->
      with_agent(state, id, fn(agent) { system.map(agent.save(agent), Saved) })
    model.Export(id, path) ->
      with_agent(state, id, fn(agent) {
        system.map(agent.export(agent, path), fn(_) { Exported })
      })
    model.Load(reference) ->
      case state.model.shell {
        Some(shell) -> spawn(state, load(reference, shell))
        None -> state
      }
  }
}

/// Ask the terminal to put text on the system clipboard.
fn osc52(text) {
  "\u{1b}]52;c;"
  <> bit_array.base64_encode(bit_array.from_string(text), True)
  <> "\u{07}"
}

/// Start work on the agent, for the entry `id`.
fn with_agent(state: State(_), id, work) {
  case state.model.agent {
    Some(agent) -> start(state, id, work(agent))
    None -> failed(state, id, "The agent has not started")
  }
}

fn scroll(state: State(_), delta) {
  let drawn = state.drawn
  let last = int.max(0, drawn.total - drawn.history.size.height)
  let top = int.clamp(drawn.top + delta, 0, last)
  State(..state, top: Some(top), drawn: view.Drawn(..drawn, top:))
}
