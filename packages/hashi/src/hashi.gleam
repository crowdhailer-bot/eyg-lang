//// Starting the page.
////
//// The workspace is handed in rather than fetched. `eyg/context.eyg` is part
//// of the page, so the page has it before the first frame; nothing about
//// this application needs the network to be up.

import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/time/timestamp
import gleam/uri
import hashi/state
import hashi/view
import lustre
import lustre/effect
import ogre/origin
import pal/system
import plinth/browser/document
import plinth/browser/event as pevent
import plinth/browser/location
import plinth/browser/window

pub fn main(context: String) -> Nil {
  let app = lustre.application(do_init, do_update, view.render)
  let here = window.location(window.self())
  let assert Ok(origin) = origin.from_string(location.origin(here))
  let config = state.Config(origin:, context:, puzzle: state.daily(day(here)))
  let assert Ok(_runtime) = lustre.start(app, "#app", config)
  Nil
}

/// Which board to play, counted in days from the epoch.
///
/// `?day=` names one. Everybody gets the same board on the same day, and a
/// tutorial, a recording or a bug report can name the board it is about.
fn day(here) -> Int {
  case location.search(here) {
    // `search` comes without its leading question mark.
    Ok(search) ->
      case uri.parse_query(search) {
        Ok(query) ->
          case list.key_find(query, "day") {
            Ok(day) -> result.unwrap(int.parse(day), today())
            Error(Nil) -> today()
          }
        Error(Nil) -> today()
      }
    Error(Nil) -> today()
  }
}

fn today() -> Int {
  let #(seconds, _) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds / 86_400
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch([keys(), ..list.map(actions, run)]))
}

/// Every key on the page goes to the application, which decides whether it is
/// a shell command or something being typed. The shell has no text box to hold
/// focus, so listening on one element would lose the keys as soon as a prompt
/// opened and closed.
fn keys() {
  use dispatch <- effect.from
  use event: pevent.Event(pevent.UIEvent(pevent.KeyboardEvent)) <- document.add_event_listener(
    "keydown",
  )
  // Held control, or command on a mac, comes through as one name. The shell
  // needs to tell `Enter`, which finishes typing a name, from the `Enter` that
  // runs the program.
  let name = case pevent.ctrl_key(event) || pevent.meta_key(event) {
    True -> "Mod+" <> pevent.key(event)
    False -> pevent.key(event)
  }
  dispatch(state.UserPressedKey(name))
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
