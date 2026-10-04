//// Renderer-side lifecycle for the isolated Gleam evaluator.

import filepath
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/result
import gleam/string
import plinthx/bun
import plinthx/bun/subprocess
import plinthx/javascript/module
import plinthx/node/process
import plinthx/node/url
import terminal/cell
import terminal/protocol as p

pub opaque type Runtime {
  Runtime(child: subprocess.Subprocess, stopped: cell.Cell(Bool))
}

pub fn start(emit, environment) {
  use host <- result.try(bun.get() |> result.replace_error("Bun is required"))
  use parent <- result.try(
    process.get() |> result.replace_error("Process API is unavailable"),
  )
  use cwd <- result.try(process.cwd(parent))
  use location <- result.try(url.file_url_to_path(module.url()))
  let worker =
    location
    |> filepath.directory_name
    |> filepath.join("../../../overlay_terminal/worker.mjs")
  let stopped = cell.new(False)
  let env =
    dict.merge(dict.from_list(process.env(parent)), dict.from_list(environment))
    |> dict.to_list
  let options =
    subprocess.Options(
      cwd:,
      env:,
      stdin: "ignore",
      stdout: "ignore",
      stderr: "pipe",
      serialization: "json",
      ipc: fn(raw, _) {
        case cell.read(stopped) {
          True -> Nil
          False -> receive(raw, emit)
        }
      },
    )
  use child <- result.try(subprocess.spawn(
    host,
    [process.exec_path(parent), worker],
    options,
  ))
  let stop_on_exit = fn(_) {
    let _ = subprocess.kill(child, "SIGTERM")
    Nil
  }
  let listener = process.once_exit(parent, stop_on_exit)
  case listener {
    Error(error) -> {
      let _ = subprocess.kill(child, "SIGTERM")
      Error(error)
    }
    Ok(_) -> {
      let stderr = case subprocess.stderr(child) {
        Ok(stream) -> subprocess.readable_stream_to_text(host, stream)
        Error(_) -> promise.resolve(Ok(""))
      }
      let _ =
        subprocess.exited(child)
        |> promise.await(fn(exit) {
          let _ = process.remove_exit_listener(parent, stop_on_exit)
          use stderr <- promise.map(stderr)
          case cell.read(stopped) {
            True -> Nil
            False -> {
              let message = result.unwrap(stderr, "") |> string.trim
              let message = case message {
                "" ->
                  "EYG runtime exited ("
                  <> case exit {
                    Ok(code) -> int.to_string(code)
                    Error(error) -> error
                  }
                  <> ")"
                _ -> message
              }
              emit(p.Failure(0, message))
            }
          }
        })
      Ok(Runtime(child, stopped))
    }
  }
}

fn receive(raw, emit) {
  case decode.run(raw, decode.string) {
    Ok(text) ->
      case json.parse(text, p.event_decoder()) {
        Ok(event) -> emit(event)
        Error(_) -> emit(p.Failure(0, "Invalid runtime event"))
      }
    Error(_) -> emit(p.Failure(0, "Invalid runtime message"))
  }
}

pub fn send(runtime: Runtime, request) {
  case cell.read(runtime.stopped) {
    True -> Error("Runtime has stopped")
    False ->
      request
      |> p.encode_request
      |> json.to_string
      |> dynamic.string
      |> subprocess.send(runtime.child, _)
  }
}

pub fn terminate(runtime: Runtime) {
  case cell.read(runtime.stopped) {
    True -> Nil
    False -> {
      cell.write(runtime.stopped, True)
      let _ = subprocess.kill(runtime.child, "SIGTERM")
      Nil
    }
  }
  subprocess.exited(runtime.child)
}
