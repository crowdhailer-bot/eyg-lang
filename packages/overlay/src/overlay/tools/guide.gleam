//// Read a guide on writing EYG.
////
//// Guides are fetched by the harness from the hub origin, not by agent code,
//// so a policy that denies fetch does not stop the agent learning EYG.

import castor
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/string
import oas/generator/utils
import ogre/origin.{type Origin}
import overlay/llm/tool

pub const name: String = "guide"

pub const description: String = "Read a guide on writing EYG code. Guides are syntax, builtins and http-fetch."

/// The available guides and the path they are served from.
pub const guides = [
  #("syntax", "/guides/eyg-syntax-guide.md"),
  #("builtins", "/guides/builtins-reference.md"),
  #("http-fetch", "/guides/http-fetch.md"),
]

pub fn parameters() -> List(#(String, castor.Ref(castor.Schema), Bool)) {
  [
    castor.field("name", castor.string()),
  ]
}

pub fn spec() -> tool.Tool {
  tool.Tool(name, description, parameters())
}

pub fn cast(
  arguments: Dict(String, utils.Any),
) -> Result(String, List(decode.DecodeError)) {
  let arguments = utils.fields_to_dynamic(arguments)
  decode.run(arguments, decode.field("name", decode.string, decode.success))
}

/// The request for a guide, or an error listing the available guides.
pub fn request(
  origin: Origin,
  guide: String,
) -> Result(Request(BitArray), String) {
  case list.key_find(guides, guide) {
    Ok(path) ->
      origin.to_request(origin)
      |> request.set_method(http.Get)
      |> request.set_path(path)
      |> request.set_body(<<>>)
      |> Ok
    Error(Nil) ->
      Error(
        "unknown guide `"
        <> guide
        <> "`, available guides are: "
        <> string.join(list.map(guides, fn(g) { g.0 }), ", "),
      )
  }
}

pub fn response(response: Response(BitArray)) -> Result(String, String) {
  case response.status, bit_array.to_string(response.body) {
    200, Ok(text) -> Ok(text)
    200, Error(Nil) -> Error("guide is not valid utf-8")
    status, _ ->
      Error("failed to fetch guide, status " <> int.to_string(status))
  }
}
