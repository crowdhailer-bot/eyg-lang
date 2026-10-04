//// Process lifecycle and command scheduling are Gleam application policy.
//// Prompt replies bypass the evaluation queue so a suspended effect can resume.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import plinthx/node/process
import terminal/cell
import terminal/driver
import terminal/overlay
import terminal/protocol as p
import terminal/repl

type Runtime {
  Repl(repl.Runtime)
  Overlay(overlay.Runtime)
}

pub fn main() {
  let assert Ok(process) = process.get()
  let runtime = cell.new(None)
  let answer = cell.new(None)
  let active_id = cell.new(0)
  let emit = fn(event) {
    let _ =
      p.encode_event(event)
      |> json.to_string
      |> dynamic.string
      |> process.send(process, _)
    Nil
  }
  let prompt = fn(text) {
    use resolve <- promise.new
    cell.write(answer, Some(resolve))
    emit(p.Prompt(cell.read(active_id), text))
  }
  let queue = cell.new(promise.resolve(Nil))
  let _ = process.on_disconnect(process, fn() { process.exit(process, 0) })
  let assert Ok(_) =
    process.on_message(process, fn(raw) {
      let decoded = case decode.run(raw, decode.string) {
        Ok(text) ->
          json.parse(text, p.request_decoder()) |> result.replace_error(Nil)
        Error(_) ->
          decode.run(raw, p.request_decoder()) |> result.replace_error(Nil)
      }
      case decoded {
        Error(_) -> emit(p.Failure(0, "Invalid terminal request"))
        Ok(p.Reply(text)) -> {
          case cell.read(answer) {
            Some(resolve) -> resolve(text)
            None -> Nil
          }
          cell.write(answer, None)
        }
        Ok(request) -> {
          let next =
            promise.await(cell.read(queue), fn(_) {
              case request {
                p.Initialize(arguments) -> {
                  let initial = case arguments {
                    ["overlay", ..] ->
                      overlay.initialize(arguments, emit, prompt)
                      |> promise.map(result.map(_, Overlay))
                    _ ->
                      repl.initialize(arguments, emit, prompt)
                      |> promise.map(result.map(_, Repl))
                  }
                  use initialized <- promise.map(initial)
                  case initialized {
                    Error(message) -> emit(p.Failure(0, message))
                    Ok(value) -> {
                      cell.write(runtime, Some(value))
                      case value {
                        Repl(repl) -> {
                          let _ =
                            repl.packages(repl)
                            |> promise.rescue(fn(error) {
                              emit(p.Failure(
                                0,
                                "Package discovery: "
                                  <> driver.error_message(error),
                              ))
                            })
                          Nil
                        }
                        Overlay(_) -> Nil
                      }
                    }
                  }
                }
                p.Structure(action) -> {
                  cell.write(active_id, 0)
                  case cell.read(runtime) {
                    Some(Repl(runtime)) -> repl.structure(runtime, action)
                    _ -> Nil
                  }
                  promise.resolve(Nil)
                }
                p.Evaluate(id, source, structural) -> {
                  cell.write(active_id, id)
                  case cell.read(runtime) {
                    Some(Repl(runtime)) ->
                      repl.evaluate(runtime, id, source, structural)
                    Some(Overlay(runtime)) ->
                      overlay.evaluate(runtime, id, source)
                    None -> {
                      emit(p.Failure(id, "Runtime is not initialized"))
                      promise.resolve(Nil)
                    }
                  }
                }
                p.Reply(_) -> promise.resolve(Nil)
              }
            })
            |> promise.rescue(fn(error) {
              emit(p.Failure(cell.read(active_id), driver.error_message(error)))
            })
          cell.write(queue, next)
        }
      }
    })
  Nil
}
