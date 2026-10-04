import eyg/analysis/type_/binding
import eyg/cli/shell
import eyg/interpreter/simple_debug
import eyg/ir/tree
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import loam/execute
import morph/buffer
import morph/manipulation as m
import terminal/cell
import terminal/driver
import terminal/projection
import terminal/protocol as p
import tui/bridge
import tui/structural

type State {
  State(
    scope: execute.Scope,
    definitions: List(#(String, tree.Node(#(Int, Int)), #(Int, Int))),
    execution: execute.State,
    revision: Int,
    pending: String,
    editor: buffer.Buffer,
    input: Option(#(m.UserInput, String, String)),
    previous: List(buffer.Buffer),
    after: Option(buffer.Buffer),
    reference_types: List(#(tree.Reference, binding.Poly)),
    loading: List(tree.Reference),
    fetches: List(String),
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
  use initialized <- promise.map(driver.drive(bridge.initialize(arguments), io))
  use #(scope, execution) <- result.map(initialized)
  let state =
    State(
      scope:,
      definitions: [],
      execution:,
      revision: 0,
      pending: "",
      editor: structural.empty(scope, execution),
      input: None,
      previous: [],
      after: None,
      reference_types: [],
      loading: [],
      fetches: [],
    )
  emit(p.Ready(bridge.cache_names(execution)))
  Runtime(cell.new(state), id, io, emit)
}

pub fn packages(runtime: Runtime) {
  let snapshot = cell.read(runtime.state)
  let io = driver.IO(..runtime.io, fetch: fn(_) { Nil })
  use #(execution, names) <- promise.map(driver.drive(
    bridge.packages(snapshot.execution),
    io,
  ))
  let current = cell.read(runtime.state)
  case current.revision == snapshot.revision {
    True ->
      cell.write(
        runtime.state,
        State(..current, execution:, revision: current.revision + 1),
      )
    False -> Nil
  }
  runtime.emit(p.Packages(names))
}

pub fn structure(runtime: Runtime, action: p.Action) {
  let state = cell.read(runtime.state)
  case action {
    p.Enter(Some(source)) -> {
      case structural.parse(source, state.scope, state.execution) {
        Error(message) -> runtime.emit(p.Failure(0, message))
        Ok(editor) -> {
          cell.write(runtime.state, State(..state, editor:, input: None))
          publish(runtime, None)
        }
      }
    }
    _ -> {
      let #(next, message) = act(state, action, runtime.emit)
      cell.write(runtime.state, next)
      publish(runtime, message)
    }
  }
}

fn act(state: State, action, emit) {
  case action {
    p.Enter(_) -> #(state, None)
    p.Cancel -> #(State(..state, input: None), None)
    p.Answer(text) ->
      case state.input {
        None -> #(state, None)
        Some(#(input, _, _)) ->
          apply(
            state,
            structural.answer(input, text, state.scope, state.execution),
          )
      }
    p.Paste(text) ->
      apply(
        state,
        structural.paste(state.editor, text, state.scope, state.execution),
      )
    p.Focus(path) -> #(
      State(
        ..state,
        editor: buffer.focus_at(state.editor, path)
          |> result.unwrap(state.editor),
      ),
      None,
    )
    p.Key("y") -> {
      let message = case buffer.copy_source(state.editor) {
        Ok(text) -> {
          emit(p.Clipboard(text))
          "Copied expression"
        }
        Error(_) -> "Select an expression to copy"
      }
      #(state, Some(message))
    }
    p.Key("u") -> #(
      state,
      Some("The signing popup is a placeholder in the web workspace."),
    )
    p.Key(key) ->
      case structural.navigate(state.editor, key) {
        Ok(editor) -> #(State(..state, editor:), None)
        Error(_) -> operation(state, key)
      }
  }
}

fn apply(state, change) {
  case change {
    Ok(editor) -> #(State(..state, editor:, input: None), None)
    Error(message) -> #(state, Some(message))
  }
}

fn operation(state: State, key) {
  case key, state.previous, state.after {
    "up", [last, ..], None -> #(
      State(..state, after: Some(state.editor), editor: last),
      None,
    )
    "down", _, Some(after) -> #(
      State(..state, editor: after, after: None),
      None,
    )
    _, _, _ ->
      case structural.operation(state.editor, key, state.execution) {
        Error(_) -> #(
          state,
          Some("Cannot apply " <> key <> " at this selection"),
        )
        Ok(#(_, m.Resolved(rebuild))) -> #(
          State(
            ..state,
            editor: structural.resolve(rebuild, state.scope, state.execution),
          ),
          None,
        )
        Ok(#(label, m.UserInput(input))) -> {
          let kind = case key {
            "q" | "Q" -> "file"
            "@" -> "package"
            _ -> "text"
          }
          #(State(..state, input: Some(#(input, label, kind))), None)
        }
      }
  }
}

fn publish(runtime: Runtime, message: Option(String)) -> Nil {
  let state = cell.read(runtime.state)
  let editor =
    structural.reanalyse(state.editor, state.scope, state.reference_types)
  cell.write(runtime.state, State(..state, editor:))
  let #(type_, errors) = structural.type_info(editor)
  let input =
    option.map(state.input, fn(input) {
      let #(input, label, kind) = input
      let #(value, hints) = structural.input_details(input)
      p.Input(label, value, hints, kind)
    })
  runtime.emit(
    p.Structural(p.View(
      lines: projection.project([structural.view(editor)]),
      source: projection.project(structural.display(editor)) |> projection.text,
      type_:,
      errors:,
      message:,
      input:,
    )),
  )
  list.each(structural.references(editor), fn(reference) {
    load_reference(runtime, reference)
  })
}

fn load_reference(runtime: Runtime, reference: tree.Reference) -> Nil {
  let snapshot = cell.read(runtime.state)
  case list.contains(snapshot.loading, reference) {
    True -> Nil
    False -> {
      cell.write(
        runtime.state,
        State(..snapshot, loading: [reference, ..snapshot.loading]),
      )
      let io =
        driver.IO(..runtime.io, output: fn(_, _) { Nil }, fetch: fn(url) {
          let state = cell.read(runtime.state)
          cell.write(
            runtime.state,
            State(..state, fetches: [url, ..state.fetches]),
          )
        })
      let _ =
        driver.drive(
          structural.load_reference(reference, snapshot.execution),
          io,
        )
        |> promise.map(fn(loaded) {
          let #(type_, execution) = loaded
          let current = cell.read(runtime.state)
          let state = case current.revision == snapshot.revision {
            True -> State(..current, execution:, revision: current.revision + 1)
            False -> current
          }
          let state = case type_ {
            Ok(type_) ->
              State(..state, reference_types: [
                #(reference, type_),
                ..state.reference_types
              ])
            Error(_) -> state
          }
          cell.write(runtime.state, state)
          publish(runtime, case type_ {
            Ok(_) -> None
            Error(_) ->
              Some("Unable to load " <> tree.reference_to_string(reference))
          })
        })
        |> promise.rescue(fn(error) {
          publish(
            runtime,
            Some(
              "Unable to load "
              <> tree.reference_to_string(reference)
              <> ": "
              <> driver.error_message(error),
            ),
          )
        })
      Nil
    }
  }
}

pub fn evaluate(runtime: Runtime, id, source, from_structure) {
  cell.write(runtime.id, id)
  let state = cell.read(runtime.state)
  let started = driver.now()
  case from_structure {
    True ->
      list.each(list.reverse(state.fetches), fn(url) {
        runtime.emit(p.Fetch(id, url))
      })
    False -> Nil
  }
  let code = case state.pending {
    "" -> source
    pending -> pending <> "\n" <> source
  }
  let observe = fn(label, input, output) {
    runtime.emit(p.Effect(
      id,
      p.EffectRecord(
        label,
        simple_debug.inspect(input),
        simple_debug.inspect(output),
        None,
      ),
    ))
  }
  let effect = case from_structure {
    True ->
      shell.handle_source_observed(
        structural.executable(state.editor),
        state.scope,
        state.definitions,
        state.execution,
        observe,
      )
    False ->
      shell.handle_observed(
        code,
        state.scope,
        state.definitions,
        state.execution,
        observe,
      )
  }
  use #(results, #(pending, scope, definitions, execution)) <- promise.map(
    driver.drive(effect, runtime.io),
  )
  let current = cell.read(runtime.state)
  let current =
    State(
      ..current,
      pending:,
      scope:,
      definitions:,
      execution:,
      revision: current.revision + 1,
      fetches: case from_structure {
        True -> []
        False -> current.fetches
      },
    )
  let clear = from_structure && !list.any(results, result.is_error)
  let current = case clear {
    True ->
      State(
        ..current,
        previous: [state.editor, ..current.previous],
        after: None,
        editor: structural.empty(scope, execution),
        input: None,
      )
    False -> current
  }
  cell.write(runtime.state, current)
  runtime.emit(p.Complete(id, results, pending, driver.now() -. started))
  case clear {
    True -> publish(runtime, None)
    False -> Nil
  }
}
