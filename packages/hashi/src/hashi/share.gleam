//// Posting a finished board to Bluesky, through spotless.run.
////
//// The harness has no `Fetch`. A program says "share this" and the platform is
//// what talks to the network, so a program can never choose the host it
//// reaches. Everything here is a request to build or an answer to read; the
//// order they go in is `hashi/platform`, and only that has to know about
//// waiting.
////
//// The flow is OAuth 2.1 device authorization, which is the one that suits a
//// page with no server of its own:
////
//// 1. ask spotless for a device code, and get back a short code for the user
//// 2. the user types that code at the verification page and approves
//// 3. poll for the token until it is granted
//// 4. look up whose account it is, and write the post
////
//// See `notes.md`: spotless.run has no `bluesky` party yet, so step 1 answers
//// with an error today. Nothing else about the flow is waiting on that.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}
import midas/effect
import ogre/origin
import spotless/device_code/device_authorization
import spotless/device_code/token as device_token
import spotless/oauth_2_1

/// The party spotless knows the account provider by.
pub const party = "bluesky"

pub fn spotless() -> origin.Origin {
  origin.https("spotless.run")
}

/// Where posts are written. This is the default Bluesky host; an account on
/// another server would need its own, which is only knowable once spotless
/// says which server the account lives on.
pub fn account_host() -> origin.Origin {
  origin.https("bsky.social")
}

/// What the user has to do before a post can be written.
pub type Grant {
  Grant(
    device_code: String,
    user_code: String,
    verification_uri: String,
    /// Seconds to leave between polls, as asked for by the server.
    interval: Int,
  )
}

/// Where a poll for the token got to.
pub type TokenOutcome {
  Granted(access_token: String)
  /// The user has not approved it yet. Wait and ask again.
  Pending
  Refused(String)
}

// ASKING FOR A CODE -----------------------------------------------------------

pub fn device_authorization_request(client_id: String) -> Request(BitArray) {
  device_authorization.request_to_http(
    #(spotless(), "/device/" <> party),
    device_authorization.Request(client_id:, scope: []),
  )
}

pub fn read_device_authorization(
  result: Result(Response(BitArray), effect.FetchError),
) -> Result(Grant, String) {
  case result {
    Error(reason) -> Error(describe_fetch_error(reason))
    Ok(response) ->
      case device_authorization.response_from_http(response) {
        Ok(Ok(response)) -> {
          let device_authorization.Response(
            device_code:,
            user_code:,
            verification_uri:,
            interval:,
            ..,
          ) = response
          let interval = option.unwrap(interval, 5)
          Ok(Grant(device_code:, user_code:, verification_uri:, interval:))
        }
        Ok(Error(device_authorization.ErrorResponse(error:, error_description:))) ->
          Error(describe(error, error_description))
        // Not an OAuth answer at all. There is no party called bluesky yet, so
        // this is what a live spotless says today.
        Error(_) -> Error(unreadable(response))
      }
  }
}

// WAITING FOR APPROVAL --------------------------------------------------------

pub fn token_request(
  client_id: String,
  device_code: String,
) -> Request(BitArray) {
  device_token.request_to_http(
    #(spotless(), "/token"),
    device_token.Request(client_id:, device_code:),
  )
}

/// A poll that has not been approved yet comes back as a 400 with an OAuth
/// error in it, which is the protocol working rather than the request failing.
pub fn read_token(
  result: Result(Response(BitArray), effect.FetchError),
) -> TokenOutcome {
  case result {
    Error(reason) -> Refused(describe_fetch_error(reason))
    Ok(response) ->
      case oauth_2_1.token_response_from_http(response) {
        Ok(Ok(granted)) -> Granted(granted.access_token)
        // These two are the server saying "not yet", everything else is a no.
        Ok(Error(error)) ->
          case error.error {
            "authorization_pending" | "slow_down" -> Pending
            _ -> Refused(describe(error.error, error.error_description))
          }
        Error(_) -> Refused(unreadable(response))
      }
  }
}

// WRITING THE POST ------------------------------------------------------------

/// Whose account the token belongs to. A record is written to a repository and
/// the repository is named by the account's DID, which the token does not carry.
pub fn session_request(access_token: String) -> Request(BitArray) {
  origin.to_request(account_host())
  |> request.set_method(http.Get)
  |> request.set_path("/xrpc/com.atproto.server.getSession")
  |> request.prepend_header("authorization", "Bearer " <> access_token)
  |> request.prepend_header("accept", "application/json")
  |> request.set_body(<<>>)
}

pub fn read_session(
  result: Result(Response(BitArray), effect.FetchError),
) -> Result(String, String) {
  use response <- result.try(unwrap_fetch(result))
  json.parse_bits(
    response.body,
    decode.field("did", decode.string, decode.success),
  )
  |> result.replace_error("could not tell whose account that is")
}

pub fn post_request(
  access_token: String,
  did: String,
  text: String,
  at: Timestamp,
) -> Request(BitArray) {
  let body =
    json.object([
      #("repo", json.string(did)),
      #("collection", json.string("app.bsky.feed.post")),
      #(
        "record",
        json.object([
          #("$type", json.string("app.bsky.feed.post")),
          #("text", json.string(text)),
          #(
            "createdAt",
            json.string(timestamp.to_rfc3339(at, calendar.utc_offset)),
          ),
        ]),
      ),
    ])
    |> json.to_string
    |> bit_array.from_string

  origin.to_request(account_host())
  |> request.set_method(http.Post)
  |> request.set_path("/xrpc/com.atproto.repo.createRecord")
  |> request.prepend_header("authorization", "Bearer " <> access_token)
  |> request.prepend_header("content-type", "application/json")
  |> request.set_body(body)
}

pub fn read_post(
  result: Result(Response(BitArray), effect.FetchError),
) -> Result(Nil, String) {
  use _response <- result.map(unwrap_fetch(result))
  Nil
}

// ----------------------------------------------------------------------------

/// Anything that is not a 2xx is the other end saying no, and its body is the
/// most useful thing there is to say about it.
fn unwrap_fetch(
  result: Result(Response(BitArray), effect.FetchError),
) -> Result(Response(BitArray), String) {
  case result {
    Error(reason) -> Error(describe_fetch_error(reason))
    Ok(response) ->
      case response.status {
        status if status >= 200 && status < 300 -> Ok(response)
        _ -> Error(unreadable(response))
      }
  }
}

/// The other end said something that is not the protocol. Its status and body
/// are the most useful thing there is to say about that.
fn unreadable(response: Response(BitArray)) -> String {
  "the server answered "
  <> int.to_string(response.status)
  <> ": "
  <> body_text(response)
}

fn body_text(response: Response(BitArray)) -> String {
  case bit_array.to_string(response.body) {
    Ok(text) -> text
    Error(Nil) -> "an answer that was not text"
  }
}

fn describe(error: String, description: option.Option(String)) -> String {
  case description {
    Some(description) -> error <> ": " <> description
    None -> error
  }
}

fn describe_fetch_error(reason: effect.FetchError) -> String {
  case reason {
    effect.NetworkError(description) -> "network error: " <> description
    effect.UnableToReadBody -> "unable to read body"
    effect.NotImplemented -> "not implemented"
  }
}
