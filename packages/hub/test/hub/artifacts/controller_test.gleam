import eyg/hub/client
import eyg/hub/schema.{ArtifactFile}
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/string
import hub/helpers.{dispatch}
import hub/router
import ogre/operation
import wisp/simulate

fn html(text) {
  ArtifactFile("index.html", "text/html", bit_array.from_string(text))
}

const svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"

fn bundle() {
  [
    html("<img src=\"images/my pic.svg\">"),
    ArtifactFile("images/my pic.svg", "image/svg+xml", <<svg:utf8>>),
  ]
}

fn share(name, files, context) {
  let response = dispatch(client.share_artifact(name, files), context)
  client.share_artifact_response(response)
}

fn get(path, context) {
  let request = simulate.request(http.Get, path)
  let response = router.route(request, context)
  response.Response(..response, body: simulate.read_body_bits(response))
}

pub fn share_and_fetch_an_artifact_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(id)) = share("departures", bundle(), context)
  assert 36 == string.length(id)

  let response = dispatch(client.get_artifact(id), context)
  let assert Ok(Ok(#("departures", files))) =
    client.get_artifact_response(response)
  assert list.sort(bundle(), fn(a, b) { string.compare(a.path, b.path) })
    == files
}

pub fn unknown_artifacts_are_not_found_test() {
  use context <- helpers.web_context()
  assert 404 == get("/artifacts/not-an-id", context).status
  assert 404
    == get("/artifacts/00000000-0000-0000-0000-000000000000", context).status
  assert 404 == get("/artifacts/'; DROP TABLE artifacts; --", context).status
}

pub fn invalid_bundles_are_rejected_test() {
  use context <- helpers.web_context()
  assert Ok(Error("Bundle requires index.html with media_type text/html"))
    == share("a", [ArtifactFile("page.html", "text/html", <<>>)], context)
  assert Ok(Error("index.html must be UTF-8"))
    == share("a", [ArtifactFile("index.html", "text/html", <<255>>)], context)
  assert Ok(Error("Invalid or duplicate bundle path: ../secret"))
    == share(
      "a",
      [html(""), ArtifactFile("../secret", "text/plain", <<>>)],
      context,
    )
  assert Ok(Error("Invalid or duplicate bundle path: index.html"))
    == share("a", [html(""), html("")], context)
  assert Ok(Error("Invalid media type: text/html;charset=utf-8"))
    == share(
      "a",
      [html(""), ArtifactFile("b.html", "text/html;charset=utf-8", <<>>)],
      context,
    )
  assert Ok(Error("Artifact name must contain 1–120 characters"))
    == share(" ", [html("")], context)

  let request =
    operation.post("/artifacts")
    |> operation.set_header("content-type", "application/json")
    |> operation.set_body(<<"{\"name\": 1}">>)
  assert 400 == dispatch(request, context).status
}

pub fn sharing_is_rate_limited_by_address_test() {
  use context <- helpers.web_context()
  let ip = helpers.test_ip()
  let request =
    simulate.request(http.Post, "/artifacts")
    |> simulate.string_body(
      "{\"name\":\"a\",\"files\":[{\"path\":\"index.html\",\"media_type\":\"text/html\",\"content\":\"\"}]}",
    )
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-forwarded-for", ip)
  list.repeat(Nil, 30)
  |> list.each(fn(_) {
    assert 201 == router.route(request, context).status
  })
  assert 429 == router.route(request, context).status
}
