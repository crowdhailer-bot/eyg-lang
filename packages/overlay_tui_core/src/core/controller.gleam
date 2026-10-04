//// Shared terminal IO around the pure interaction reducer. A frontend supplies
//// its mount function and owns reconciliation; the controller owns native
//// input, subprocess lifetime, completion and clipboard work.

import core/native as n
import core/native_view.{type Mounted}
import gleam/bit_array
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam_opentui as o
import gleam_opentui/clipboard
import plinth/browser/microtask
import plinthx/bun
import terminal/app as a
import terminal/cell
import terminal/completion
import terminal/process
import terminal/protocol as p

pub type Handle {
  Handle(
    model: fn() -> a.Model,
    dispatch: fn(a.Message) -> Nil,
    mounted: Mounted,
    stop: fn() -> promise.Promise(Nil),
  )
}

pub type Port {
  Port(
    send: fn(p.Request) -> Result(Nil, String),
    terminate: fn() -> promise.Promise(Nil),
  )
}

pub fn start(renderer, arguments, overlay, directory, environment, mount) {
  attach(
    renderer,
    arguments,
    overlay,
    directory,
    fn(emit) {
      let runtime = process.start(emit, environment) |> n.must
      Port(fn(request) { process.send(runtime, request) }, fn() {
        process.terminate(runtime) |> promise.map(fn(_) { Nil })
      })
    },
    mount,
  )
}

/// Connect a native screen to a runtime port. Tests and benchmarks can replay
/// exactly the same event stream without timing package discovery or the model.
pub fn attach(renderer, arguments, overlay, directory, connect, mount) {
  let state = cell.new(a.new(overlay))
  let stopped = cell.new(False)
  let dispatch_ref = cell.new(fn(_: a.Message) { Nil })
  let dispatch = fn(message) {
    case cell.read(stopped) {
      True -> Nil
      False -> cell.read(dispatch_ref)(message)
    }
  }
  let mounted: Mounted = mount(renderer, cell.read(state), dispatch, directory)
  let runtime: Port = connect(fn(event) { dispatch(a.Received(event)) })
  let editor = mounted.screen.editor
  let history = mounted.screen.history
  let queue =
    microtask.get()
    |> result.replace_error("queueMicrotask unavailable")
    |> n.must
  let host = bun.get() |> result.replace_error("Bun unavailable") |> n.must
  let clipboard_ref = cell.new(None)
  let clipboard_service = fn() {
    case cell.read(clipboard_ref) {
      Some(service) -> service
      None -> {
        let service = clipboard.create("{}") |> n.must
        cell.write(clipboard_ref, Some(service))
        service
      }
    }
  }
  let pending_frame = cell.new(None)
  let stop_ref = cell.new(fn() { promise.resolve(Nil) })
  let stop = fn() { cell.read(stop_ref)() }
  let execute = fn(command) {
    case command {
      a.Send(request) ->
        case runtime.send(request) {
          Ok(_) -> Nil
          Error(error) -> dispatch(a.Received(p.Failure(0, error)))
        }
      a.Editor(text, select, prefix) -> {
        // Replace while completing so native undo retains the typed prefix.
        case prefix {
          Some(_) -> o.replace_text(editor, text) |> n.must
          None -> o.set_text(editor, text) |> n.must
        }
        case prefix {
          Some(prefix) -> {
            let lines = string.split(prefix, "\n")
            let last = list.last(lines) |> result.unwrap("")
            o.set_cursor(
              editor,
              list.length(lines) - 1,
              bun.string_width(host, last),
            )
            |> n.must
          }
          None -> Nil
        }
        case select {
          True -> {
            o.select_all(editor) |> n.must
            Nil
          }
          False -> Nil
        }
      }
      a.Complete(revision) -> {
        let model = cell.read(state)
        let _ =
          choices(model, directory)
          |> promise.map(fn(choices) {
            dispatch(a.CompletedChoices(revision, choices))
          })
        Nil
      }
      a.FollowTail -> {
        o.set_sticky_scroll(history, True) |> n.must
        o.scroll_to(history, o.scroll_height(history)) |> n.must
      }
      a.Reveal(id) -> {
        o.set_sticky_scroll(history, False) |> n.must
        case cell.read(pending_frame) {
          Some(callback) -> o.off_frame(renderer, callback) |> n.must
          None -> Nil
        }
        let callback = fn() {
          cell.write(pending_frame, None)
          o.scroll_child_into_view(history, id) |> n.must
        }
        cell.write(pending_frame, Some(callback))
        o.once_frame(renderer, callback) |> n.must
        o.request_render(renderer) |> n.must
      }
      a.Scroll(delta) -> {
        o.scroll_by(history, delta) |> n.must
      }
      a.Copy(text) -> {
        let _ = o.copy_osc52(renderer, text)
        let _ = clipboard.write_text(clipboard_service(), text)
        Nil
      }
      a.Clipboard -> {
        let _ =
          clipboard.read(
            clipboard_service(),
            "{\"preferredTypes\":[\"text/plain\"]}",
          )
          |> promise.map(fn(value) {
            let text =
              value
              |> result.replace_error(Nil)
              |> result.try(clipboard.representation)
              |> result.map(clipboard.bytes)
              |> result.try(bit_array.to_string)
              |> result.unwrap(cell.read(state).clipboard)
            case text {
              "" -> dispatch(a.Status("Clipboard is empty or unavailable"))
              _ -> dispatch(a.Paste(text))
            }
          })
        Nil
      }
      a.Exit -> {
        let _ = stop()
        Nil
      }
    }
  }
  cell.write(dispatch_ref, fn(message) {
    let #(model, commands) = a.update(cell.read(state), message)
    cell.write(state, model)
    mounted.update(model)
    list.each(commands, execute)
  })
  let highlighted = cell.new(None)
  let sample = fn() {
    case cell.read(stopped) {
      True -> Nil
      False -> {
        let source = o.plain_text(editor)
        let prefix =
          o.text_range(o.edit_buffer(editor), 0, o.cursor_offset(editor))
          |> n.must
        let cursor = string.length(prefix)
        let before = cell.read(state)
        case source != before.source || cursor != before.cursor {
          True -> dispatch(a.Changed(source, cursor))
          False -> Nil
        }
        case !overlay && cell.read(highlighted) != Some(source) {
          False -> Nil
          True -> {
            n.highlight(editor, mounted.screen.style)
            cell.write(highlighted, Some(source))
          }
        }
      }
    }
  }
  // OpenTUI reports content before its new cursor position. Read them together
  // after both notifications, and synchronously before any input submission.
  let queued = cell.new(False)
  let changed = fn() {
    case cell.read(queued) {
      True -> Nil
      False -> {
        cell.write(queued, True)
        microtask.call(queue, fn() {
          cell.write(queued, False)
          sample()
        })
        |> n.must
      }
    }
  }
  o.on_content_change(editor, changed) |> n.must
  o.on_cursor_change(editor, changed) |> n.must
  o.on_submit(editor, fn() {
    sample()
    dispatch(a.Submit)
  })
  |> n.must
  let key = fn(event) {
    sample()
    let #(name, sequence, ctrl, shift, meta) = o.key_details(event)
    case a.key(cell.read(state), name, sequence, ctrl, shift, meta) {
      Some(message) -> {
        o.prevent_key_default(event)
        dispatch(message)
      }
      None -> Nil
    }
  }
  let paste = fn(event) {
    let model = cell.read(state)
    case model.structural && a.input(model) == None && model.prompt == None {
      True -> {
        o.prevent_paste_default(event)
        case bit_array.to_string(o.paste_bytes(event)) {
          Ok(text) -> dispatch(a.Paste(text))
          Error(_) -> dispatch(a.Status("Clipboard is not UTF-8"))
        }
      }
      False -> Nil
    }
  }
  o.on_key(renderer, key) |> n.must
  o.on_paste(renderer, paste) |> n.must
  let terminated = cell.new(None)
  cell.write(stop_ref, fn() {
    case cell.read(terminated) {
      Some(done) -> done
      None -> {
        cell.write(stopped, True)
        o.off_key(renderer, key) |> n.must
        o.off_paste(renderer, paste) |> n.must
        case cell.read(pending_frame) {
          Some(callback) -> o.off_frame(renderer, callback) |> n.must
          None -> Nil
        }
        mounted.dispose()
        let done =
          runtime.terminate()
          |> promise.await(fn(_) {
            case cell.read(clipboard_ref) {
              Some(service) ->
                clipboard.dispose(service) |> promise.map(fn(_) { Nil })
              None -> promise.resolve(Nil)
            }
          })
        cell.write(terminated, Some(done))
        // Set terminated before destroy emits its own lifecycle callback.
        o.destroy_renderer(renderer) |> n.must
        done
      }
    }
  })
  o.once_destroy(renderer, fn() {
    let _ = stop()
    Nil
  })
  |> n.must
  execute(a.Send(p.Initialize(arguments)))
  Handle(fn() { cell.read(state) }, dispatch, mounted, stop)
}

fn choices(model: a.Model, directory) {
  case model.overlay || model.prompt != None {
    True -> promise.resolve([])
    False ->
      case a.input(model) {
        Some(input) ->
          case input.kind {
            "file" ->
              completion.files(
                model.source,
                string.length(model.source),
                directory,
              )
            "package" ->
              promise.resolve(completion.hints(
                model.source,
                list.map(model.packages, fn(name) { #(name, "hub package") }),
              ))
            _ -> promise.resolve(completion.hints(model.source, input.hints))
          }
        None ->
          case model.structural {
            True -> promise.resolve([])
            False ->
              completion.complete(
                model.source,
                model.cursor,
                model.packages,
                directory,
              )
          }
      }
  }
}
