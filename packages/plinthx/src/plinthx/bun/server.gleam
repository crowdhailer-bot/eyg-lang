//// Bun HTTP server APIs: https://bun.sh/docs/api/http

import gleam/javascript/promise.{type Promise}
import plinth/browser/request.{type Request}
import plinth/browser/response.{type Response}
import plinthx/bun.{type Bun}

pub type Server

pub type Options {
  Options(
    hostname: String,
    port: Int,
    fetch: fn(Request, Server) -> Promise(Response),
  )
}

@external(javascript, "../../server.ffi.mjs", "serve")
pub fn serve(bun: Bun, options: Options) -> Result(Server, String)

@external(javascript, "../../server.ffi.mjs", "port")
pub fn port(server: Server) -> Int

@external(javascript, "../../server.ffi.mjs", "stop")
pub fn stop(
  server: Server,
  close_active_connections: Bool,
) -> Promise(Result(Nil, String))
