import gleam/bit_array
import gleam/dynamic/decode
import gleam/http/request
import gleam/json
import gleam/string
import overlay/eval/fixture/repository

fn fixture() {
  let assert Ok(repository) =
    repository.load(
      "CrowdHailer",
      "eyg-lang",
      "main",
      "test/fixtures/repository",
    )
  repository
}

fn get(url) {
  let assert Ok(request) = request.to(url)
  let request = request.set_body(request, <<>>)
  let assert Ok(response) = repository.handle(fixture(), request)
  response
}

pub fn build_output_is_not_served_test() {
  assert [#("README.md", 6), #("src/app/main.eyg", 2)] == fixture().files
}

pub fn raw_files_are_served_test() {
  let response =
    get(
      "https://raw.githubusercontent.com/CrowdHailer/eyg-lang/main/src/app/main.eyg",
    )
  assert 200 == response.status
  assert <<"5\n">> == response.body
  let response =
    get(
      "https://raw.githubusercontent.com/CrowdHailer/eyg-lang/refs/heads/main/README.md",
    )
  assert <<"hello\n">> == response.body
  assert 404
    == get(
      "https://raw.githubusercontent.com/CrowdHailer/eyg-lang/main/build/output.js",
    ).status
}

pub fn the_tree_lists_files_and_directories_test() {
  let response =
    get(
      "https://api.github.com/repos/CrowdHailer/eyg-lang/git/trees/main?recursive=1",
    )
  let decoder = {
    use tree <- decode.field(
      "tree",
      decode.list({
        use path <- decode.field("path", decode.string)
        use type_ <- decode.field("type", decode.string)
        decode.success(#(path, type_))
      }),
    )
    decode.success(tree)
  }
  let assert Ok(tree) = json.parse_bits(response.body, decoder)
  assert [
      #("src", "tree"),
      #("src/app", "tree"),
      #("README.md", "blob"),
      #("src/app/main.eyg", "blob"),
    ]
    == tree
}

pub fn contents_list_directories_and_encode_files_test() {
  let response =
    get("https://api.github.com/repos/CrowdHailer/eyg-lang/contents/src")
  let assert Ok(body) = bit_array.to_string(response.body)
  assert "[{\"type\":\"dir\",\"name\":\"app\",\"path\":\"src/app\",\"size\":0}]"
    == body
  let response =
    get("https://api.github.com/repos/CrowdHailer/eyg-lang/contents/README.md")
  let assert Ok(body) = bit_array.to_string(response.body)
  assert string.contains(body, "\"content\":\"aGVsbG8K\"")
  assert 404
    == get("https://api.github.com/repos/CrowdHailer/eyg-lang/contents/missing").status
}

pub fn other_repositories_are_not_served_test() {
  let assert Ok(request) =
    request.to(
      "https://raw.githubusercontent.com/gleam-lang/stdlib/main/README.md",
    )
  assert Error(Nil)
    == repository.handle(fixture(), request.set_body(request, <<>>))
}
