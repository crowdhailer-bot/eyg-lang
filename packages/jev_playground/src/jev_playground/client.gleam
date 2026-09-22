//// Send requests to Jev with fetch, retrying temporary failures.
//// Browsers cannot call TypeSafe directly so they use a same origin proxy.

import gleam/fetch
import gleam/float
import gleam/javascript/promise.{type Promise}
import gleam/result
import gleam/string
import jev
import ogre/operation
import ogre/origin.{type Origin}
import plinth/javascript/performance

pub type Transport {
  /// Call TypeSafe with the key, for use outside the browser.
  Direct(api_key: String)
  /// Call a proxy that adds the key, `/v1/..` paths are forwarded to TypeSafe.
  Proxy(origin: Origin)
}

pub type Reply {
  Reply(evaluation: jev.Evaluation, thinking_ms: Int)
}

const attempts = 4

pub fn system_one(
  transport: Transport,
  request: jev.Request,
) -> Promise(Result(Reply, String)) {
  let operation = jev.system_one(request)
  let request = case transport {
    Direct(api_key:) -> jev.to_request(operation, api_key)
    Proxy(origin:) -> operation.to_request(operation, origin)
  }
  send(request, 0)
}

fn send(request, attempt) {
  let start = performance.now()
  use response <- promise.await(
    fetch.send_bits(request) |> promise.try_await(fetch.read_bytes_body),
  )
  let thinking_ms = float.round(performance.now() -. start)
  case response {
    Error(reason) -> promise.resolve(Error(string.inspect(reason)))
    Ok(response) ->
      case jev.system_one_response(response) {
        Ok(evaluation) -> promise.resolve(Ok(Reply(evaluation:, thinking_ms:)))
        Error(failure) ->
          case jev.retry_delay(failure, attempt), attempt < attempts {
            Ok(delay), True -> {
              use Nil <- promise.await(promise.wait(delay))
              send(request, attempt + 1)
            }
            _, _ -> {
              let id = jev.request_id(response) |> result.unwrap("unknown")
              promise.resolve(Error(
                string.inspect(failure) <> " request id " <> id,
              ))
            }
          }
      }
  }
}
