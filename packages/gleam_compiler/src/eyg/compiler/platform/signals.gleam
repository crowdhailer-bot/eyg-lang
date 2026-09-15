//// Experimental signals for updating the DOM.
////
//// `host` keeps the signal graph in the page, see `signals_runtime.mjs`.
//// A signal is an integer handle to a string, effect types are not
//// polymorphic so a signal can not hold any value.
////
//// `Derive` takes a function with an empty effect row, the type guarantees
//// the page can call it whenever an input changes without running a handler.
////
//// Signals built in EYG with a state handler need only `WriteText` from
//// `dom.selectors`, see the examples.

import eyg/analysis/type_/isomorphic as t
import eyg/compiler/platform/browser.{type Effect}

fn fallible(value) {
  t.result(value, t.String)
}

pub fn host() -> List(Effect) {
  [
    #("Signal", #(t.String, t.Integer)),
    #("Get", #(t.Integer, fallible(t.String))),
    #(
      "Set",
      #(
        t.record([#("signal", t.Integer), #("value", t.String)]),
        fallible(t.unit),
      ),
    ),
    #(
      "Derive",
      #(
        t.record([
          #("inputs", t.List(t.Integer)),
          #("compute", t.Fun(t.List(t.String), t.Empty, t.String)),
        ]),
        fallible(t.Integer),
      ),
    ),
    #(
      "BindText",
      #(
        t.record([#("selector", t.String), #("signal", t.Integer)]),
        fallible(t.unit),
      ),
    ),
  ]
}
