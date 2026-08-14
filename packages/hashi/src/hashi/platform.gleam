//// Carrying out the six effects of the harness.
////
//// Five of them are answers about the puzzle and are given straight away, so
//// the whole of a program that reads the board and builds bridges runs without
//// ever leaving the page. Only `ShareOutcome` has to go anywhere, and where it
//// goes is decided here rather than by the program: the harness has no `Fetch`,
//// so a program can ask for its result to be shared and cannot ask for
//// anything else to be sent anywhere.
////
//// The puzzle is the host state, threaded through every effect, so running a
//// program is a function of the board and not of anything kept on the side.

import eyg/interpreter/state as istate
import gleam/time/timestamp
import gleam/uri
import hashi/game
import hashi/harness
import hashi/share
import ogre/origin
import overlay/web/environment.{
  type Environment, type Handling, Environment, Unknown, Working,
}
import pal/system

/// How many times to ask whether the user has approved the post before giving
/// up. At the interval spotless asks for this is a few minutes.
const poll_attempts = 60

pub type Host {
  Host(
    game: game.Game,
    /// Where the page is served from. Spotless takes this as the client id, so
    /// a device code is asked for in the name of the page asking.
    origin: origin.Origin,
  )
}

pub fn environment(
  host: Host,
  briefing: String,
  scope: List(#(String, istate.Value(environment.Meta))),
) -> Environment(Host) {
  Environment(
    host:,
    handler: handle,
    briefing:,
    effects: harness.types(harness.effects()),
    scope:,
  )
}

pub fn handle(
  host: Host,
  label: String,
  lift: istate.Value(environment.Meta),
) -> #(Host, Handling) {
  case harness.cast(label, lift) {
    Error(reason) -> #(host, Unknown(reason))
    Ok(effect) -> perform(host, effect)
  }
}

fn perform(host: Host, effect: harness.Effect) -> #(Host, Handling) {
  let Host(game: board, origin:) = host
  case effect {
    harness.ListIslands -> #(
      host,
      immediately(harness.islands_encode(game.islands(board))),
    )
    harness.ListBridges -> #(
      host,
      immediately(harness.bridges_encode(game.bridges(board))),
    )
    harness.AddBridge(start:, end:) -> {
      let #(board, outcome) = game.add_bridge(board, start, end)
      #(
        Host(..host, game: board),
        immediately(harness.add_bridge_encode(outcome)),
      )
    }
    harness.Undo -> {
      let #(board, moved) = game.undo(board)
      #(Host(..host, game: board), immediately(harness.step_encode(moved)))
    }
    harness.Redo -> {
      let #(board, moved) = game.redo(board)
      #(Host(..host, game: board), immediately(harness.step_encode(moved)))
    }
    harness.ShareOutcome(text) -> #(host, Working(post(origin, text)))
  }
}

fn immediately(value) -> Handling {
  Working(system.Done(value))
}

// SHARING ---------------------------------------------------------------------

fn post(origin: origin.Origin, text: String) {
  let client_id = origin.to_string(origin)
  use answer <- system.Fetch(share.device_authorization_request(client_id))
  case share.read_device_authorization(answer) {
    Error(reason) -> refused(reason)
    Ok(share.Grant(device_code:, user_code:, verification_uri:, interval:)) -> {
      use <- announce(user_code, verification_uri)
      poll(client_id, device_code, interval, poll_attempts, text)
    }
  }
}

/// Tell the user the code, then open the page they type it into.
fn announce(user_code: String, verification_uri: String, then) {
  use <- system.Alert(
    "Enter the code " <> user_code <> " to approve this post.",
  )
  case uri.parse(verification_uri) {
    Ok(uri) -> {
      use _ <- system.Visit(uri)
      then()
    }
    Error(Nil) -> then()
  }
}

fn poll(client_id, device_code, interval, remaining, text) {
  case remaining {
    0 -> refused("gave up waiting for the post to be approved")
    _ -> {
      use answer <- system.Fetch(share.token_request(client_id, device_code))
      case share.read_token(answer) {
        share.Granted(access_token) -> publish(access_token, text)
        share.Refused(reason) -> refused(reason)
        share.Pending -> {
          use <- system.Sleep(interval * 1000)
          poll(client_id, device_code, interval, remaining - 1, text)
        }
      }
    }
  }
}

fn publish(access_token: String, text: String) {
  use answer <- system.Fetch(share.session_request(access_token))
  case share.read_session(answer) {
    Error(reason) -> refused(reason)
    Ok(did) -> {
      let request =
        share.post_request(access_token, did, text, timestamp.system_time())
      use answer <- system.Fetch(request)
      case share.read_post(answer) {
        Ok(Nil) -> system.Done(harness.share_outcome_encode(Ok(Nil)))
        Error(reason) -> refused(reason)
      }
    }
  }
}

fn refused(reason: String) {
  system.Done(harness.share_outcome_encode(Error(reason)))
}
