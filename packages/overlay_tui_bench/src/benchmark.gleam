//// Typed access for the common benchmark harness. The harness needs JavaScript
//// to load the unchanged TypeScript baseline alongside generated Gleam modules.
//// Every new foreign binding remains in plinthx.

import core/controller
import core/native as n
import gleam/javascript/promise
import gleam/json
import gleam/result
import gleam_opentui/testing as t
import gleam_opentui/tree_sitter
import terminal/app as a
import terminal/protocol as p

pub type Session {
  Session(setup: t.TestRendererSetup, handle: controller.Handle)
}

pub fn start(overlay, mount) {
  use setup <- promise.map(t.create("{\"width\":110,\"height\":34}"))
  let setup = n.must(setup)
  let handle =
    controller.attach(
      t.renderer(setup),
      [],
      overlay,
      "benchmark",
      fn(emit) {
        controller.Port(
          fn(request) {
            case request {
              p.Initialize(_) ->
                emit(case overlay {
                  True -> p.OverlayReady("benchmark")
                  False -> p.Ready(["standard"])
                })
              _ -> Nil
            }
            Ok(Nil)
          },
          fn() { promise.resolve(Nil) },
        )
      },
      mount,
    )
  Session(setup, handle)
}

pub fn emit(session: Session, event_json) {
  let event =
    json.parse(event_json, p.event_decoder())
    |> result.replace_error("Invalid benchmark event")
    |> n.must
  session.handle.dispatch(a.Received(event))
}

pub fn render(session: Session) {
  t.render_once(session.setup) |> promise.map(n.must)
}

pub fn capture(session: Session) {
  t.capture(session.setup)
}

pub fn type_text(session: Session, text) {
  t.type_text(t.input(session.setup), text) |> promise.map(n.must)
}

pub fn key(session: Session, name) {
  t.press_key(t.input(session.setup), name, False, False, False) |> n.must
}

pub fn stop(session: Session) {
  session.handle.stop()
}

pub fn warm_parser() {
  use initialized <- promise.await(tree_sitter.initialize(
    tree_sitter.get() |> n.must,
  ))
  n.must(initialized)
  use loaded <- promise.map(tree_sitter.preload_parser(
    tree_sitter.get() |> n.must,
    "markdown",
  ))
  let assert True = n.must(loaded)
  Nil
}

pub fn drain_parser() {
  use performance <- promise.await(tree_sitter.get_performance(
    tree_sitter.get() |> n.must,
  ))
  let _ = n.must(performance)
  promise.wait(0)
}
