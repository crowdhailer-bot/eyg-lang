//// Fetch: https://fetch.spec.whatwg.org/

pub type Response

pub type Request

pub type ResponseConstructor

@external(javascript, "./fetch_ffi.mjs", "getResponse")
pub fn get_response() -> Result(ResponseConstructor, Nil)

@external(javascript, "./fetch_ffi.mjs", "newResponse")
pub fn new_response(
  constructor: ResponseConstructor,
  body: String,
  status: Int,
  headers: List(#(String, String)),
) -> Result(Response, String)
