//// Starting the page.
////
//// The workspace is handed in rather than fetched. `eyg/context.eyg` is part
//// of the page, so the page has it before the first frame; nothing about
//// this application needs the network to be up.

import gleam/javascript/promise
import gleam/list
import gleam/time/timestamp
import hashi/state
import hashi/view
import lustre
import lustre/effect
import ogre/origin
import pal/system
import plinth/browser/location
import plinth/browser/window

pub fn main(context: String) -> Nil {
  let app = lustre.application(do_init, do_update, view.render)
  let browser_origin = location.origin(window.location(window.self()))
  let assert Ok(origin) = origin.from_string(browser_origin)
  let config = state.Config(origin:, context:, puzzle: state.daily(today()))
  let assert Ok(_runtime) = lustre.start(app, "#app", config)
  Nil
}

/// Which day it is, counted from the epoch.
fn today() -> Int {
  let #(seconds, _) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds / 86_400
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, run)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, run)))
}

fn run(action) {
  effect.from(fn(dispatch) {
    promise.map(system.run(action), dispatch)
    Nil
  })
}
