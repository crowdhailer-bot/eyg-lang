//// `eyg tui`, the shell drawn with étui. The loop owns the terminal and the
//// shell: it advances the shell's work a slice at a time and polls for keys
//// in between, so the screen stays responsive while EYG runs.

import etui/backend
import etui/backend/default
import etui/geometry
import etui/terminal
import eyg/cli/internal/config
import eyg/cli/tui/model.{type Model}
import eyg/cli/tui/shell.{type Shell}
import eyg/cli/tui/view
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string as text
import loam/system
import plinthx/javascript/string
import simplifile

/// Work the shell has been asked to do, returning to the loop when finished.
type Outcome {
  Started(Result(Shell, String))
  Evaluated(shell.Evaluated)
}

type Work {
  Idle
  Working(
    id: Int,
    started: Float,
    next: Promise(Result(#(List(shell.Event), shell.Progress(Outcome)), String)),
  )
  Waiting(id: Int, started: Float, resume: fn(String) -> system.Effect(Outcome))
}

type State(backend) {
  State(
    model: Model,
    work: Work,
    term: terminal.Terminal(backend),
    top: Option(Int),
    drawn: view.Drawn,
    quit: Bool,
  )
}

/// Milliseconds between frames, and of work between polls for input.
const frame = 16

pub fn run(input) -> Promise(Nil) {
  use loaded <- promise.await(system.run(config.load()))
  use home <- promise.await(system.run(system.env("HOME")))
  case loaded {
    Error(_) -> {
      io.println_error("failed to load config")
      promise.resolve(Nil)
    }
    Ok(config) -> {
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
        model: model.new(directory),
        work: Idle,
        term:,
        top: None,
        drawn: view.empty(),
        quit: False,
      )
      |> start(0, system.map(shell.start(input, config), Started))
      |> loop
    }
  }
}

fn loop(state: State(_)) -> Promise(Nil) {
  case state.quit {
    True -> {
      terminal.restore(state.term)
      promise.resolve(Nil)
    }
    False -> {
      let state = draw(state)
      case state.work {
        Working(id:, started:, next:) -> {
          let progressed = promise.map(next, Some)
          let waited = promise.map(promise.wait(frame), fn(_) { None })
          use raced <- promise.await(promise.race_list([progressed, waited]))
          let state = case raced {
            Some(progressed) -> progress(state, id, started, progressed)
            None -> state
          }
          poll(state, 0)
        }
        Idle | Waiting(..) -> poll(state, frame)
      }
    }
  }
}

fn poll(state: State(_), timeout) {
  use polled <- promise.await(terminal.poll(state.term, timeout))
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
  shell.advance(effect, int.to_float(frame))
  |> promise.map(Ok)
  |> promise.rescue(fn(error) {
    Error(string.from(error) |> result.unwrap("Unknown JavaScript error"))
  })
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
        shell.Finished(Started(Error(message))) -> failed(state, id, message)
        shell.Finished(Evaluated(evaluated)) -> {
          let duration = shell.now() -. started
          State(
            ..state,
            model: model.completed(state.model, id, evaluated, duration),
            work: Idle,
          )
        }
      }
    }
  }
}

fn failed(state: State(_), id, message) {
  State(..state, model: model.failed(state.model, id, message), work: Idle)
}

fn input(state: State(_), event) {
  case event {
    backend.KeyPress(key) -> apply(state, model.key(state.model, key))
    backend.Paste(text) -> State(..state, model: model.paste(state.model, text))
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
    model.Evaluate(id, source) ->
      case state.model.shell {
        Some(current) ->
          start(
            state,
            id,
            system.map(shell.evaluate(current, source), Evaluated),
          )
        None -> failed(state, id, "The shell has not started")
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
  }
}

fn scroll(state: State(_), delta) {
  let drawn = state.drawn
  let last = int.max(0, drawn.total - drawn.history.size.height)
  let top = int.clamp(drawn.top + delta, 0, last)
  State(..state, top: Some(top), drawn: view.Drawn(..drawn, top:))
}
