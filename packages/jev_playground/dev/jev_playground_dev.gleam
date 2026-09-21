//// Serve the playground from `dist` and proxy `/v1/..` requests to TypeSafe.
//// The proxy adds the API key from `TYPESAFE_API_KEY` so it never reaches the browser.
//// Build first with `jev_playground_build`, this server does not bundle to keep its memory small.
//// `gleam run -m jev_playground_dev --runtime bun` then open http://localhost:8095

import filepath
import gleam/fetch
import gleam/http/response
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import glen
import glen_node
import jev
import ogre/operation
import plinth/node/process
import simplifile

pub const port = 8095

pub fn main() {
  let key = list.key_find(array.to_list(process.env()), "TYPESAFE_API_KEY")
  case key {
    Ok(_) -> Nil
    Error(Nil) ->
      io.println("TYPESAFE_API_KEY is not set, only demos will work")
  }
  let assert Ok(_) = glen_node.serve(port, handle(_, key))
  io.println("serving on http://localhost:" <> int.to_string(port))
}

fn handle(request: glen.Request, key) {
  case glen.path_segments(request) {
    ["v1", ..] -> proxy(request, key)
    ["assets", name] ->
      case simplifile.read_bits(filepath.join("dist/assets", name)) {
        Ok(bits) ->
          response.new(200)
          |> response.prepend_header("content-type", mime(name))
          |> response.set_body(glen.Bits(bits))
          |> promise.resolve
        Error(_) -> promise.resolve(not_found())
      }
    ["favicon.ico"] -> promise.resolve(not_found())
    _ ->
      case simplifile.read("dist/index.html") {
        Ok(html) ->
          response.new(200)
          |> response.prepend_header("content-type", "text/html")
          |> response.set_body(glen.Text(html))
          |> promise.resolve
        Error(_) -> promise.resolve(text(500, "run jev_playground_build first"))
      }
  }
}

fn mime(name) {
  case filepath.extension(name) {
    Ok("css") -> "text/css"
    Ok("mjs") | Ok("js") -> "application/javascript"
    Ok("json") -> "application/json"
    _ -> "application/octet-stream"
  }
}

fn not_found() {
  response.new(404) |> response.set_body(glen.Empty)
}

fn proxy(request: glen.Request, key) {
  case key {
    Error(Nil) ->
      promise.resolve(text(503, "TYPESAFE_API_KEY is not set on the server"))
    Ok(key) -> {
      use body <- promise.await(glen.read_body_bits(request))
      let body = result.unwrap(body, <<>>)
      let operation =
        operation.Operation(
          method: request.method,
          path: request.path,
          query: request.query,
          headers: [#("content-type", "application/json")],
          body:,
        )
      let upstream = jev.to_request(operation, key)
      use reply <- promise.map(
        fetch.send_bits(upstream) |> promise.try_await(fetch.read_bytes_body),
      )
      case reply {
        Ok(reply) -> {
          let passed =
            list.filter(reply.headers, fn(header) {
              list.contains(
                ["content-type", "retry-after", "x-typesafe-request-id"],
                header.0,
              )
            })
          response.Response(
            status: reply.status,
            headers: passed,
            body: glen.Bits(reply.body),
          )
        }
        Error(reason) -> text(502, string.inspect(reason))
      }
    }
  }
}

fn text(status, message) {
  response.new(status)
  |> response.prepend_header("content-type", "text/plain")
  |> response.set_body(glen.Text(message))
}
