//// WHATWG Fetch Request: https://fetch.spec.whatwg.org/#request-class

import gleam/javascript/promise.{type Promise}

pub type Request

@external(javascript, "./fetch_ffi.mjs", "text")
pub fn text(request: Request) -> Promise(Result(String, String))
