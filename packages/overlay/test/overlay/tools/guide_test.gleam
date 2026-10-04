import gleam/http/response
import ogre/origin
import overlay/tools/guide

pub fn request_known_guide_test() {
  let assert Ok(request) = guide.request(origin.https("eyg.run"), "syntax")
  assert request.host == "eyg.run"
  assert request.path == "/guides/eyg-syntax-guide.md"
}

pub fn request_unknown_guide_test() {
  assert guide.request(origin.https("eyg.run"), "nope")
    == Error(
      "unknown guide `nope`, available guides are: syntax, builtins, http-fetch",
    )
}

pub fn response_test() {
  let ok = response.new(200) |> response.set_body(<<"# Guide":utf8>>)
  assert guide.response(ok) == Ok("# Guide")
  let missing = response.new(404) |> response.set_body(<<>>)
  assert guide.response(missing) == Error("failed to fetch guide, status 404")
}
