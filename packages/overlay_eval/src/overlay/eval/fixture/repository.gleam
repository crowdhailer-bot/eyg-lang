//// A local checkout served as if from GitHub.
////
//// Agents that read their own source code fetch files from
//// raw.githubusercontent.com and list them with the GitHub API. The fixture
//// answers those requests from a directory, so evals read a known version of
//// the source and never reach the network.

import filepath
import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile

pub type Repository {
  Repository(
    owner: String,
    name: String,
    branch: String,
    root: String,
    // Paths relative to the root, with their size in bytes.
    files: List(#(String, Int)),
  )
}

/// Directories never served, build output and version control.
const skipped = ["build", "node_modules", "_build", "target"]

/// Serve the files under `root` as the `branch` of `owner/name`.
pub fn load(
  owner: String,
  name: String,
  branch: String,
  root: String,
) -> Result(Repository, String) {
  use files <- result.map(walk(root, ""))
  let files = list.sort(files, fn(a, b) { string.compare(a.0, b.0) })
  Repository(owner:, name:, branch:, root:, files:)
}

fn walk(root, relative) -> Result(List(#(String, Int)), String) {
  let directory = filepath.join(root, relative)
  use names <- result.try(
    simplifile.read_directory(directory)
    |> result.map_error(fn(reason) {
      "unable to list "
      <> directory
      <> ": "
      <> simplifile.describe_error(reason)
    }),
  )
  list.try_fold(names, [], fn(acc, name) {
    let path = case relative {
      "" -> name
      _ -> relative <> "/" <> name
    }
    let full = filepath.join(root, path)
    case string.starts_with(name, "."), list.contains(skipped, name) {
      True, _ | _, True -> Ok(acc)
      False, False ->
        case simplifile.is_directory(full) {
          Ok(True) -> result.map(walk(root, path), list.append(acc, _))
          _ ->
            case simplifile.file_info(full) {
              Ok(info) -> Ok([#(path, info.size), ..acc])
              Error(_) -> Ok(acc)
            }
        }
    }
  })
}

/// Answer a request if it is for this repository on GitHub.
pub fn handle(
  repository: Repository,
  request: Request(BitArray),
) -> Result(Response(BitArray), Nil) {
  let Repository(owner:, name:, branch:, ..) = repository
  case request.method, request.host, request.path_segments(request) {
    http.Get, "raw.githubusercontent.com", [o, n, "refs", "heads", b, ..path]
    | http.Get, "raw.githubusercontent.com", [o, n, b, ..path]
      if o == owner && n == name && b == branch
    -> Ok(raw(repository, string.join(path, "/")))
    http.Get, "api.github.com", ["repos", o, n, "git", "trees", b]
      if o == owner && n == name && b == branch
    -> Ok(tree(repository))
    http.Get, "api.github.com", ["repos", o, n, "contents", ..path]
      if o == owner && n == name
    -> Ok(contents(repository, string.join(path, "/")))
    _, _, _ -> Error(Nil)
  }
}

fn raw(repository: Repository, path) {
  case read(repository, path) {
    Ok(bytes) -> response.new(200) |> response.set_body(bytes)
    Error(Nil) -> not_found()
  }
}

fn read(repository: Repository, path) {
  case list.key_find(repository.files, path) {
    Ok(_) ->
      simplifile.read_bits(filepath.join(repository.root, path))
      |> result.replace_error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

fn tree(repository: Repository) {
  let directories =
    list.flat_map(repository.files, fn(file) { parents(file.0) })
    |> set.from_list
    |> set.to_list
    |> list.sort(string.compare)
    |> list.map(fn(path) {
      json.object([#("path", json.string(path)), #("type", json.string("tree"))])
    })
  let files =
    list.map(repository.files, fn(file) {
      json.object([
        #("path", json.string(file.0)),
        #("type", json.string("blob")),
        #("size", json.int(file.1)),
      ])
    })
  json.object([
    #("tree", json.preprocessed_array(list.append(directories, files))),
    #("truncated", json.bool(False)),
  ])
  |> json_response(200)
}

fn contents(repository: Repository, path) {
  case read(repository, path) {
    Ok(bytes) ->
      json.object([
        #("type", json.string("file")),
        #("name", json.string(filepath.base_name(path))),
        #("path", json.string(path)),
        #("size", json.int(bit_array.byte_size(bytes))),
        #("encoding", json.string("base64")),
        #("content", json.string(bit_array.base64_encode(bytes, True))),
      ])
      |> json_response(200)
    Error(Nil) ->
      case children(repository, path) {
        [] -> not_found()
        entries -> json_response(json.preprocessed_array(entries), 200)
      }
  }
}

fn children(repository: Repository, directory) {
  let prefix = case directory {
    "" -> ""
    _ -> directory <> "/"
  }
  list.filter_map(repository.files, fn(file) {
    let #(path, size) = file
    case string.starts_with(path, prefix) {
      False -> Error(Nil)
      True ->
        case
          string.split_once(string.drop_start(path, string.length(prefix)), "/")
        {
          Error(Nil) -> Ok(#(path, "file", size))
          Ok(#(name, _)) -> Ok(#(prefix <> name, "dir", 0))
        }
    }
  })
  |> list.unique
  |> list.map(fn(entry) {
    let #(path, type_, size) = entry
    json.object([
      #("type", json.string(type_)),
      #("name", json.string(filepath.base_name(path))),
      #("path", json.string(path)),
      #("size", json.int(size)),
    ])
  })
}

fn parents(path) {
  case list.reverse(string.split(path, "/")) {
    [_, ..above] -> do_parents(above, [])
    [] -> []
  }
}

fn do_parents(segments, acc) {
  case segments {
    [] -> acc
    [_, ..rest] ->
      do_parents(rest, [string.join(list.reverse(segments), "/"), ..acc])
  }
}

fn json_response(body, status) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(<<json.to_string(body):utf8>>)
}

fn not_found() {
  json.object([#("message", json.string("Not Found"))])
  |> json_response(404)
}
