//// Experimental WebRTC data channel effects, see `webrtc_runtime.mjs`.
////
//// - `mirror` follows the browser API, peers and channels are handles and
////   every step of the offer and answer exchange is an effect.
//// - `batch` the mirror with many messages sent or received in one effect.
//// - `session` an offer and an answer are tokens the program moves between
////   peers, SDP and ICE are not visible.
////
//// Candidates are gathered before a description is returned, so no effect
//// is needed for trickle ICE.

import eyg/analysis/type_/isomorphic as t
import eyg/compiler/platform/browser.{type Effect}
import gleam/list

fn fallible(value) {
  t.result(value, t.String)
}

pub fn mirror() -> List(Effect) {
  [
    #("CreatePeer", #(t.unit, t.Integer)),
    #(
      "CreateChannel",
      #(
        t.record([#("peer", t.Integer), #("label", t.String)]),
        fallible(t.Integer),
      ),
    ),
    #("AcceptChannel", #(t.Integer, fallible(t.Integer))),
    #("CreateOffer", #(t.Integer, fallible(t.String))),
    #(
      "CreateAnswer",
      #(
        t.record([#("peer", t.Integer), #("offer", t.String)]),
        fallible(t.String),
      ),
    ),
    #(
      "SetAnswer",
      #(
        t.record([#("peer", t.Integer), #("answer", t.String)]),
        fallible(t.unit),
      ),
    ),
    #("WaitOpen", #(t.Integer, fallible(t.unit))),
    #(
      "Send",
      #(
        t.record([#("channel", t.Integer), #("data", t.Binary)]),
        fallible(t.unit),
      ),
    ),
    #("Receive", #(t.Integer, fallible(t.Binary))),
    #("Close", #(t.Integer, t.unit)),
  ]
}

pub fn batch() -> List(Effect) {
  list.append(mirror(), [
    #(
      "SendAll",
      #(
        t.record([#("channel", t.Integer), #("messages", t.List(t.Binary))]),
        fallible(t.unit),
      ),
    ),
    #(
      "ReceiveAll",
      #(
        t.record([#("channel", t.Integer), #("min", t.Integer)]),
        fallible(t.List(t.Binary)),
      ),
    ),
  ])
}

pub fn session() -> List(Effect) {
  let session = t.record([#("session", t.Integer), #("token", t.String)])
  [
    #("Offer", #(t.String, fallible(session))),
    #("Accept", #(t.String, fallible(session))),
    #("Connect", #(session, fallible(t.unit))),
    #("Ready", #(t.Integer, fallible(t.unit))),
    #(
      "Send",
      #(
        t.record([#("session", t.Integer), #("data", t.Binary)]),
        fallible(t.unit),
      ),
    ),
    #("Receive", #(t.Integer, fallible(t.Binary))),
  ]
}
