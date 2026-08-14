import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/http/response
import gleam/json
import gleam/option.{Some}
import gleam/set
import gleam/string
import hashi/game
import hashi/harness
import hashi/platform
import ogre/origin
import overlay/web/environment
import pal/system
import shared/hashi

fn position(x, y) {
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}

/// Two islands on a row, one bridge apart.
fn host() {
  let puzzle =
    hashi.from_islands_and_connections(
      width: 4,
      height: 1,
      islands: set.from_list([#(0, 0), #(3, 0)]),
      connections: [#(#(0, 0), #(3, 0), hashi.Single)],
    )
  platform.Host(game: game.new(puzzle), origin: origin.https("hashi.test"))
}

pub fn listing_the_islands_answers_at_once_test() {
  let #(host, handling) = platform.handle(host(), "ListIslands", v.unit())
  let assert environment.Working(system.Done(value)) = handling
  assert value
    == harness.islands_encode([
      harness.Island(position: #(0, 0), target: 1),
      harness.Island(position: #(3, 0), target: 1),
    ])
  assert [] == game.bridges(host.game)
}

pub fn building_a_bridge_changes_the_board_test() {
  let lift =
    v.Record(
      dict.from_list([#("start", position(0, 0)), #("end", position(3, 0))]),
    )
  let #(host, handling) = platform.handle(host(), "AddBridge", lift)
  let assert environment.Working(system.Done(value)) = handling
  assert value == v.ok(v.unit())
  assert game.bridges(host.game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 1)]

  let #(_, handling) = platform.handle(host, "ListBridges", v.unit())
  let assert environment.Working(system.Done(value)) = handling
  assert value
    == harness.bridges_encode([
      harness.Bridge(start: #(0, 0), end: #(3, 0), count: 1),
    ])
}

pub fn a_refused_bridge_leaves_the_board_alone_test() {
  let lift =
    v.Record(
      dict.from_list([#("start", position(1, 0)), #("end", position(3, 0))]),
    )
  let #(host, handling) = platform.handle(host(), "AddBridge", lift)
  let assert environment.Working(system.Done(value)) = handling
  assert value == v.error(v.Tagged("BadStart", v.unit()))
  assert [] == game.bridges(host.game)
}

pub fn undo_and_redo_walk_the_board_back_and_forward_test() {
  let lift =
    v.Record(
      dict.from_list([#("start", position(0, 0)), #("end", position(3, 0))]),
    )
  let #(host, _) = platform.handle(host(), "AddBridge", lift)

  let #(host, handling) = platform.handle(host, "Undo", v.unit())
  let assert environment.Working(system.Done(value)) = handling
  assert value == v.true()
  assert [] == game.bridges(host.game)

  let #(host, handling) = platform.handle(host, "Redo", v.unit())
  let assert environment.Working(system.Done(value)) = handling
  assert value == v.true()
  assert game.bridges(host.game)
    == [harness.Bridge(start: #(0, 0), end: #(3, 0), count: 1)]

  let #(_, handling) = platform.handle(host, "Redo", v.unit())
  let assert environment.Working(system.Done(value)) = handling
  assert value == v.false()
}

pub fn nothing_outside_the_harness_is_reachable_test() {
  let #(_, handling) = platform.handle(host(), "Fetch", v.unit())
  assert handling
    == environment.Unknown(break.UnhandledEffect("Fetch", v.unit()))
}

pub fn sharing_asks_spotless_for_a_device_code_test() {
  let #(_, handling) =
    platform.handle(host(), "ShareOutcome", v.String("solved it"))
  let assert environment.Working(system.Fetch(request:, resume: _)) = handling
  assert "spotless.run" == request.host
  assert "/device/bluesky" == request.path
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "client_id=https%3A%2F%2Fhashi.test")
}

pub fn sharing_gives_up_when_spotless_has_no_such_party_test() {
  let #(_, handling) =
    platform.handle(host(), "ShareOutcome", v.String("solved it"))
  let assert environment.Working(system.Fetch(request: _, resume:)) = handling
  let answer =
    Ok(
      response.new(404)
      |> response.set_body(bit_array.from_string("Not found")),
    )
  let assert system.Done(value) = resume(answer)
  let assert v.Tagged("Error", v.String(reason)) = value
  assert string.contains(reason, "404")
}

pub fn an_approved_post_is_written_to_bluesky_test() {
  let #(_, handling) =
    platform.handle(host(), "ShareOutcome", v.String("solved it"))
  let assert environment.Working(system.Fetch(request: _, resume:)) = handling

  let grant =
    json.object([
      #("device_code", json.string("dev-1")),
      #("user_code", json.string("WXYZ")),
      #("verification_uri", json.string("https://spotless.run/verify")),
      #("expires_in", json.int(600)),
      #("interval", json.int(1)),
    ])
    |> json.to_string
  let assert system.Alert(message, resume) = resume(answered(200, grant))
  assert string.contains(message, "WXYZ")

  let assert system.Visit(uri:, resume:) = resume()
  assert Some("spotless.run") == uri.host

  // not approved yet
  let pending =
    json.to_string(
      json.object([#("error", json.string("authorization_pending"))]),
    )
  let assert system.Fetch(request:, resume:) = resume(Error("no popup"))
  assert "/token" == request.path
  let assert system.Sleep(1000, resume) = resume(answered(400, pending))

  let token =
    json.to_string(
      json.object([
        #("access_token", json.string("tok-1")),
        #("token_type", json.string("Bearer")),
      ]),
    )
  let assert system.Fetch(request: _, resume:) = resume()
  let assert system.Fetch(request:, resume:) = resume(answered(200, token))
  assert "/xrpc/com.atproto.server.getSession" == request.path

  let session =
    json.to_string(json.object([#("did", json.string("did:plc:a"))]))
  let assert system.Fetch(request:, resume:) = resume(answered(200, session))
  assert "/xrpc/com.atproto.repo.createRecord" == request.path
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "solved it")

  let assert system.Done(value) = resume(answered(200, "{}"))
  assert value == v.ok(v.unit())
}

fn answered(status, body) {
  Ok(
    response.new(status)
    |> response.set_body(bit_array.from_string(body)),
  )
}
