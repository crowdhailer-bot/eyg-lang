//// Effects available to compiled programs running in a browser.
////
//// The touch grass browser harness, implemented in `browser.mjs`, and effects
//// defined only for the compiler. The extensions reuse touch grass
//// definitions where the CLI already has one.

import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import gleam/list
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/cryptography/sign
import touch_grass/harness/browser as harness
import touch_grass/sleep
import touch_grass/uri

pub type Effect =
  #(String, #(binding.Mono, binding.Mono))

/// Every effect in the touch grass browser harness.
pub fn touch_grass() -> List(Effect) {
  list.map(harness.effects(), fn(interface) {
    #(interface.name, #(interface.lift_type, interface.lower_type))
  })
}

/// Effects that are not in the touch grass browser harness.
///
/// - `Sleep` resumes after a number of milliseconds, the harness has a TODO for it.
/// - `Hash`, `CreateKey` and `Sign` have the CLI definitions, implemented with WebCrypto.
/// - `StorageGet`, `StorageSet` and `StorageDelete` use local storage, which
///   can be unavailable so every operation can fail.
/// - `Location` is the URL of the page.
pub fn extensions() -> List(Effect) {
  [
    #(sleep.label, #(sleep.lift(), sleep.lower())),
    #(hash.label, #(hash.lift(), hash.lower())),
    #(create_key.label, #(create_key.lift(), create_key.lower())),
    #(sign.label, #(sign.lift(), sign.lower())),
    #("StorageGet", #(t.String, t.result(t.option(t.String), t.String))),
    #(
      "StorageSet",
      #(
        t.record([#("key", t.String), #("value", t.String)]),
        t.result(t.unit, t.String),
      ),
    ),
    #("StorageDelete", #(t.String, t.result(t.unit, t.String))),
    #("Location", #(t.unit, uri.uri())),
  ]
}

pub fn effects() -> List(Effect) {
  list.append(touch_grass(), extensions())
}
