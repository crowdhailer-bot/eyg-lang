//// Fetch modules from an EYG hub by content id, the local hub by default.
//// `EYG_HUB` sets the origin, the modules are served at `/modules/<cid>`.

import eyg/ir/tree as ir
import gleam/fetch
import gleam/http/request
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import jev_playground/library
import plinth/node/process

pub fn origin() -> String {
  list.key_find(array.to_list(process.env()), "EYG_HUB")
  |> result.unwrap("http://localhost:8080")
}

pub fn module(cid: String) -> Promise(Result(ir.Node(Nil), String)) {
  let url = origin() <> "/modules/" <> cid
  case request.to(url) {
    Error(Nil) -> promise.resolve(Error("not a url " <> url))
    Ok(request) -> {
      use response <- promise.map(
        fetch.send(request) |> promise.try_await(fetch.read_bytes_body),
      )
      case response {
        Ok(response) if response.status == 200 -> library.decode(response.body)
        Ok(response) ->
          Error(url <> " answered " <> int.to_string(response.status))
        Error(_) -> Error("could not fetch " <> url)
      }
    }
  }
}
