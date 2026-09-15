//// Experimental effects for the DOM, several designs for the same capability.
////
//// Every EYG value can be serialised so a live node can not be a value.
//// The designs differ in how a program refers to a node:
////
//// - `handles` an integer indexing a table of nodes kept by the page,
////   every read and write is its own effect.
//// - `selectors` a CSS selector resolved again by every effect.
//// - `snapshot` a subtree read as a value.
//// - `patch` a list of operations on handles applied in one effect.
//// - `render` a description of the children of a node, the page updates the
////   DOM to match.
////
//// A tree is a flat list of nodes each with its depth, the same shape as the
//// tokens of DecodeJSON, because EYG has no recursive types.
//// The implementations are in `dom_runtime.mjs`.

import eyg/analysis/type_/isomorphic as t
import eyg/compiler/platform/browser.{type Effect}

fn fallible(value) {
  t.result(value, t.String)
}

/// A tree of elements and text as a list of nodes with depth.
pub fn nodes() {
  t.List(
    t.record([
      #("depth", t.Integer),
      #(
        "node",
        t.union([
          #(
            "Element",
            t.record([
              #("tag", t.String),
              #("attributes", t.key_value_list(t.String)),
            ]),
          ),
          #("Text", t.String),
        ]),
      ),
    ]),
  )
}

pub fn handles() -> List(Effect) {
  let node = t.record([#("node", t.Integer), #("name", t.String)])
  [
    #("Query", #(t.String, fallible(t.List(t.Integer)))),
    #("ReadText", #(t.Integer, fallible(t.String))),
    #("ReadAttribute", #(node, fallible(t.option(t.String)))),
    #("ReadValue", #(t.Integer, fallible(t.String))),
    #("Children", #(t.Integer, fallible(t.List(t.Integer)))),
    #("Release", #(t.Integer, t.unit)),
    #(
      "Listen",
      #(
        t.record([#("node", t.Integer), #("event", t.String)]),
        fallible(t.unit),
      ),
    ),
    #(
      "NextEvent",
      #(
        t.unit,
        t.record([
          #("node", t.Integer),
          #("event", t.String),
          #("value", t.String),
        ]),
      ),
    ),
    #("CreateElement", #(t.String, fallible(t.Integer))),
    #("CreateText", #(t.String, t.Integer)),
    #(
      "SetAttribute",
      #(
        t.record([
          #("node", t.Integer),
          #("name", t.String),
          #("value", t.String),
        ]),
        fallible(t.unit),
      ),
    ),
    #(
      "SetText",
      #(t.record([#("node", t.Integer), #("text", t.String)]), fallible(t.unit)),
    ),
    #(
      "Append",
      #(
        t.record([#("parent", t.Integer), #("child", t.Integer)]),
        fallible(t.unit),
      ),
    ),
    #("Remove", #(t.Integer, fallible(t.unit))),
  ]
}

/// Creating and editing with one effect per operation, the same as handles.
pub fn imperative() -> List(Effect) {
  handles()
}

pub fn selectors() -> List(Effect) {
  [
    #("ReadText", #(t.String, fallible(t.String))),
    #("ReadAll", #(t.String, fallible(t.List(t.String)))),
    #(
      "ReadAttribute",
      #(
        t.record([#("selector", t.String), #("name", t.String)]),
        fallible(t.option(t.String)),
      ),
    ),
    #("ReadValue", #(t.String, fallible(t.String))),
    #(
      "WriteText",
      #(
        t.record([#("selector", t.String), #("text", t.String)]),
        fallible(t.unit),
      ),
    ),
    #(
      "WriteAttribute",
      #(
        t.record([
          #("selector", t.String),
          #("name", t.String),
          #("value", t.String),
        ]),
        fallible(t.unit),
      ),
    ),
    #(
      "On",
      #(
        t.record([#("selector", t.String), #("event", t.String)]),
        fallible(t.unit),
      ),
    ),
    #(
      "NextEvent",
      #(
        t.unit,
        t.record([
          #("selector", t.String),
          #("event", t.String),
          #("value", t.String),
        ]),
      ),
    ),
  ]
}

pub fn snapshot() -> List(Effect) {
  [#("Snapshot", #(t.String, fallible(nodes())))]
}

/// A node created earlier in the same patch, by index, or an existing handle.
pub fn reference() {
  t.union([#("New", t.Integer), #("Existing", t.Integer)])
}

pub fn operation() {
  let ref = reference()
  t.union([
    #("Create", t.String),
    #("CreateText", t.String),
    #(
      "SetAttribute",
      t.record([#("node", ref), #("name", t.String), #("value", t.String)]),
    ),
    #("SetText", t.record([#("node", ref), #("text", t.String)])),
    #("Append", t.record([#("parent", ref), #("child", ref)])),
    #("Remove", ref),
  ])
}

pub fn patch() -> List(Effect) {
  [
    #("Query", #(t.String, fallible(t.List(t.Integer)))),
    #("Patch", #(t.List(operation()), fallible(t.List(t.Integer)))),
  ]
}

/// Attributes named `on:event` are not set, the value is the message of
/// the event returned by NextEvent.
pub fn render() -> List(Effect) {
  [
    #(
      "Render",
      #(
        t.record([#("selector", t.String), #("nodes", nodes())]),
        fallible(t.unit),
      ),
    ),
    #(
      "NextEvent",
      #(t.unit, t.record([#("message", t.String), #("value", t.String)])),
    ),
  ]
}
