import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/option.{Some}
import morph/buffer
import ogre/origin
import pal/system
import website/config
import website/routes/workspace/state.{State}

pub fn execute_expression_test() {
  let state = with_source(ir.add(ir.integer(7), ir.integer(21)))
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(28)) == value
  assert [] == effects
}

pub fn execute_sync_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let state = with_source(source)
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(0)) == value
  // TODO keep list of effects
  assert [] == effects
}

pub fn execute_async_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("Beep")])
  let state = with_source(source)
  let assert #(state, [effect]) = command(state, "Enter")
  let assert state.RunningShell([], state.Handling(0, ..)) = state.mode
  let assert system.Alert("Beep", resume) = effect
  let assert system.Done(message) = resume()
  let assert #(state, []) = state.update(state, message)

  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.unit()) == value
  // TODO keep list of effects
  assert [] == effects
}

pub fn execute_relative_workspace_reference_test() {
  let state =
    with_modules(ir.relative("./local.eyg.json"), [
      #("local", ir.integer(42)),
    ])

  let assert #(state, []) = command(state, "Enter")
  let assert [state.Previous(value:, ..)] = state.previous
  assert Some(v.Integer(42)) == value
}

pub fn execute_nested_relative_workspace_references_test() {
  let state =
    with_modules(ir.relative("./dir/middle.eyg.json"), [
      #("dir/middle", ir.relative("./leaf.eyg.json")),
      #("dir/leaf", ir.integer(42)),
    ])

  let assert #(state, []) = command(state, "Enter")
  let assert [state.Previous(value:, ..)] = state.previous
  assert Some(v.Integer(42)) == value
}

pub fn missing_relative_workspace_reference_stops_test() {
  let state = with_source(ir.relative("./missing.eyg.json"))
  let assert #(state, []) = command(state, "Enter")
  let assert state.RunningShell(
    [],
    state.Exception(break.UndefinedReference(ir.Relative(location))),
  ) = state.mode
  assert "./missing.eyg.json" == location
}

pub fn cyclic_relative_workspace_references_stop_test() {
  let state =
    with_modules(ir.relative("./a.eyg.json"), [
      #("a", ir.relative("./b.eyg.json")),
      #("b", ir.relative("./a.eyg.json")),
    ])

  let assert #(state, []) = command(state, "Enter")
  let assert state.RunningShell(
    [],
    state.Exception(break.UndefinedReference(_)),
  ) = state.mode
}

pub fn failing_relative_workspace_module_keeps_its_error_test() {
  let state =
    with_modules(ir.relative("./broken.eyg.json"), [
      #("broken", ir.variable("missing")),
    ])

  let assert #(state, []) = command(state, "Enter")
  let assert state.RunningShell(
    [],
    state.Exception(break.UndefinedVariable("missing")),
  ) = state.mode
}

pub fn relative_workspace_module_fetches_remote_dependencies_test() {
  let state =
    with_modules(ir.relative("./local.eyg.json"), [
      #("local", ir.reference(dag_json.vacant_cid)),
    ])

  let assert #(state, [system.Fetch(..)]) = command(state, "Enter")
  let assert state.RunningShell([], state.Blocked(..)) = state.mode
  let assert #(state, []) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(
        dag_json.vacant_cid,
        Ok(ir.integer(42)),
      )),
    )
  let assert [state.Previous(value:, ..)] = state.previous
  assert Some(v.Integer(42)) == value
}

fn command(state, key) {
  state.update(state, state.UserPressedCommandKey(key))
}

fn with_source(source) {
  let assert #(state, [_pull]) = state.init(config())
  State(
    ..state,
    repl: buffer.from_source(
      source,
      repl_context(state),
      cache.types(state.cache),
    ),
  )
}

fn with_modules(source, modules) {
  let state = with_source(source)
  let modules =
    modules
    |> list.map(fn(module) {
      let #(name, source) = module
      #(
        #(name, state.EygJson),
        buffer.from_source(source, infer.pure(), dict.new()),
      )
    })
    |> dict.from_list
  State(..state, modules:)
}

fn repl_context(_state) {
  // TODO this needs to be the real REPL context
  infer.pure()
}

fn config() {
  config.Config(origin: origin.https("eyg.text"))
}
