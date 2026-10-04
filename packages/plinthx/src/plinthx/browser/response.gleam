//// WHATWG Fetch Response: https://fetch.spec.whatwg.org/#response-class

pub type Response

pub type Options {
  Options(status: Int, headers: List(#(String, String)))
}

@external(javascript, "./fetch_ffi.mjs", "newResponse")
pub fn new(body: String, options: Options) -> Result(Response, String)
