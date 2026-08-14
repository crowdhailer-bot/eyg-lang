import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import gleam/time/timestamp
import gleam/uri
import hashi/share
import midas/effect

fn answered(status, body) {
  Ok(
    response.new(status)
    |> response.set_body(bit_array.from_string(body)),
  )
}

pub fn the_code_is_asked_for_from_the_bluesky_party_test() {
  let request = share.device_authorization_request("https://hashi.test")
  assert http.Post == request.method
  assert "spotless.run" == request.host
  assert "/device/bluesky" == request.path
  let assert Ok(body) = bit_array.to_string(request.body)
  let assert Ok(params) = uri.parse_query(body)
  assert Ok("https://hashi.test") == list.key_find(params, "client_id")
}

pub fn a_granted_code_carries_what_the_user_has_to_do_test() {
  let body =
    json.object([
      #("device_code", json.string("dev-1")),
      #("user_code", json.string("WXYZ-1234")),
      #("verification_uri", json.string("https://spotless.run/verify")),
      #("expires_in", json.int(600)),
      #("interval", json.int(3)),
    ])
    |> json.to_string

  assert share.read_device_authorization(answered(200, body))
    == Ok(share.Grant(
      device_code: "dev-1",
      user_code: "WXYZ-1234",
      verification_uri: "https://spotless.run/verify",
      interval: 3,
    ))
}

pub fn a_missing_party_is_reported_as_it_comes_test() {
  let assert Error(reason) =
    share.read_device_authorization(answered(404, "Not found"))
  assert string.contains(reason, "404")
  assert string.contains(reason, "Not found")
}

pub fn a_network_failure_is_reported_test() {
  let assert Error(reason) =
    share.read_device_authorization(Error(effect.NetworkError("offline")))
  assert string.contains(reason, "offline")
}

pub fn polling_before_approval_is_pending_test() {
  let body = json.object([#("error", json.string("authorization_pending"))])
  assert share.read_token(answered(400, json.to_string(body))) == share.Pending
}

pub fn being_asked_to_slow_down_is_still_pending_test() {
  let body = json.object([#("error", json.string("slow_down"))])
  assert share.read_token(answered(400, json.to_string(body))) == share.Pending
}

pub fn a_denied_request_is_refused_test() {
  let body =
    json.object([
      #("error", json.string("access_denied")),
      #("error_description", json.string("the user said no")),
    ])
  let assert share.Refused(reason) =
    share.read_token(answered(400, json.to_string(body)))
  assert string.contains(reason, "access_denied")
  assert string.contains(reason, "the user said no")
}

pub fn an_approved_request_hands_over_the_token_test() {
  let body =
    json.object([
      #("access_token", json.string("tok-1")),
      #("token_type", json.string("Bearer")),
    ])
  assert share.read_token(answered(200, json.to_string(body)))
    == share.Granted("tok-1")
}

pub fn the_session_says_whose_account_it_is_test() {
  let request = share.session_request("tok-1")
  assert http.Get == request.method
  assert "bsky.social" == request.host
  assert "/xrpc/com.atproto.server.getSession" == request.path
  assert Ok("Bearer tok-1") == request_header(request, "authorization")

  let body =
    json.object([
      #("did", json.string("did:plc:abc")),
      #("handle", json.string("someone.bsky.social")),
    ])
  assert share.read_session(answered(200, json.to_string(body)))
    == Ok("did:plc:abc")
}

pub fn a_post_is_written_to_the_accounts_own_repository_test() {
  let at = timestamp.from_unix_seconds(1_700_000_000)
  let request =
    share.post_request("tok-1", "did:plc:abc", "solved in 12 moves", at)
  assert http.Post == request.method
  assert "/xrpc/com.atproto.repo.createRecord" == request.path
  assert Ok("Bearer tok-1") == request_header(request, "authorization")

  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"repo\":\"did:plc:abc\"")
  assert string.contains(body, "app.bsky.feed.post")
  assert string.contains(body, "solved in 12 moves")
  assert string.contains(body, "2023-11-14T22:13:20")
}

pub fn a_rejected_post_says_what_the_server_said_test() {
  let assert Error(reason) =
    share.read_post(answered(403, "{\"error\":\"RepoNotFound\"}"))
  assert string.contains(reason, "RepoNotFound")
}

pub fn an_accepted_post_is_the_end_of_it_test() {
  assert share.read_post(answered(200, "{}")) == Ok(Nil)
}

fn request_header(request: request.Request(BitArray), name) {
  list.key_find(request.headers, name)
}
