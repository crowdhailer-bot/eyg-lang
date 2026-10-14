//// Convenience facade over the existing native Fetch Response bindings.
import gleam/result
import plinthx/browser/fetch
pub type Response = fetch.Response
pub type Options { Options(status: Int, headers: List(#(String, String))) }
pub fn new(body: String, options: Options) {
  use constructor <- result.try(fetch.get_response() |> result.replace_error("Response API unavailable"))
  fetch.new_response(constructor, body, options.status, options.headers)
}
