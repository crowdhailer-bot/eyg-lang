//// What the agent is working in.
////
//// Overlay runs EYG programs on behalf of a model. The running of a program is
//// always the same; what a program is allowed to reach is not. In the browser
//// it is the browser: fetch, the clipboard, an alert. Embedded in an
//// application it is that application and nothing else.
////
//// An environment is the whole of that difference:
////
//// - `host` is the application state the effects act on, threaded through
////   every effect so nothing has to be kept in a mutable box on the side.
//// - `handler` carries out one effect against that state.
//// - `effects` are the names and types the model is shown.
//// - `briefing` is what the model is told about the place before the effects
////   are listed. This is where a context readme goes.
////
//// The browser environment lives in `overlay/web/environment/browser` and is
//// what overlay itself uses. An application embedding overlay writes its own.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/state as istate
import pal/system

pub type Meta =
  List(Int)

/// What is to be done about an effect a program performed.
pub type Handling {
  /// Stop the program. The reason is reported to whoever ran it, the same as
  /// an `Abort`.
  Stopped(String)
  /// Do some work. The program resumes with the value the work returns. Use
  /// `system.Done` for work that finishes immediately.
  Working(system.Effect(istate.Value(Meta)))
  /// Nothing here answers to that name.
  Unknown(istate.Reason(Meta))
}

/// Carry out a single effect. The effect label and the value it was performed
/// with come in with the application state, the new state comes out.
pub type Handler(host) =
  fn(host, String, istate.Value(Meta)) -> #(host, Handling)

pub type Environment(host) {
  Environment(
    host: host,
    handler: Handler(host),
    briefing: String,
    effects: List(#(String, #(t.Type(Int), t.Type(Int)))),
  )
}

/// Replace the application state, leaving how it is reached alone.
pub fn set_host(
  environment: Environment(host),
  host: host,
) -> Environment(host) {
  Environment(..environment, host:)
}
