import eyg/embedding/beam
import eyg/embedding/packages
import eyg/hub/publisher
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/parser
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import midas/continuation
import midas/effect
import multiformats/cid/v1
import untethered/ledger/schema
import untethered/substrate

pub type Mode {
  Normal
  NetworkFailure
  Corrupt
  MissingModule
  MissingPackage
}

pub fn tree(source) {
  let assert Ok(tree) = parser.all_from_string(source)
  tree
}

pub fn cid(tree) {
  cid.from_tree(tree, fn(bytes) {
    continuation.return(crypto.hash(crypto.Sha256, bytes))
  })(fn(value) { value })
}

pub fn content(tree) {
  "#" <> v1.to_string(cid(tree))
}

pub fn entry(name, version, cursor, module_tree) {
  let identity = cid(tree("0"))
  let release = publisher.Release(name, version, cid(module_tree))
  let payload =
    publisher.encode(substrate.Entry(
      version,
      None,
      identity,
      "test-key",
      release,
    ))
    |> json.to_string
  schema.ArchivedEntry(
    cursor,
    identity,
    payload,
    identity,
    version,
    None,
    "release",
  )
}

pub fn standard(root, dependencies, mode) {
  fixture(
    [
      entry("standard", 1, 1, tree("0")),
      entry("standard", 2, 2, root),
    ],
    [root, ..dependencies],
    mode,
  )
}

pub fn fixture(entries, trees, mode) {
  let calls = process.new_subject()
  let modules =
    dict.from_list(
      list.map(trees, fn(tree) {
        #(v1.to_string(cid(tree)), dag_json.to_block(tree))
      }),
    )
  let loader =
    packages.Loader(
      "https://hub.test",
      fn(request) {
        process.send(calls, request.path)
        continuation.return(reply(request, entries, modules, mode))
      },
      beam.hash,
    )
  #(loader, calls)
}

pub fn requests(calls) {
  case process.receive(calls, 0) {
    Ok(path) -> [path, ..requests(calls)]
    Error(_) -> []
  }
}

fn reply(
  req: request.Request(BitArray),
  entries: List(schema.ArchivedEntry),
  modules,
  mode,
) {
  case mode, req.path {
    NetworkFailure, _ -> Error(effect.NetworkError("offline"))
    _, "/packages/pull" -> {
      let since =
        request.get_query(req)
        |> result.try(list.key_find(_, "since"))
        |> result.try(int.parse)
        |> result.unwrap(0)
      let page = case mode {
        MissingPackage -> []
        _ ->
          list.filter(entries, fn(entry) { entry.cursor > since })
          |> list.take(1)
      }
      let body =
        schema.entries_response_encode(page)
        |> json.to_string
        |> bit_array.from_string
      Ok(response.Response(200, [], body))
    }
    _, "/modules/" <> id -> {
      case mode {
        Corrupt -> Ok(response.Response(200, [], dag_json.to_block(tree("99"))))
        MissingModule -> Ok(response.Response(204, [], <<>>))
        _ ->
          case dict.get(modules, id) {
            Ok(body) -> Ok(response.Response(200, [], body))
            Error(_) -> Ok(response.Response(204, [], <<>>))
          }
      }
    }
    _, _ -> Error(effect.NetworkError("unexpected request"))
  }
}
