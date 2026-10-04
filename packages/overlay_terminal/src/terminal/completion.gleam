//// Completion offsets count graphemes. The frontend converts the native
//// editor's prefix to this coordinate space before calling complete.

import filepath
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/regexp
import gleam/result
import gleam/string
import plinthx/node/fs

pub type Completion {
  Completion(label: String, detail: String, insert: String, from: Int, to: Int)
}

pub fn complete(source, cursor, packages, cwd) {
  let before = string.slice(source, 0, cursor)
  let assert Ok(imported) = regexp.from_string("\\bimport\\s+\"([^\"\\n]*)$")
  let assert Ok(named) = regexp.from_string("@([a-zA-Z0-9_-]*)$")
  case regexp.scan(imported, before) {
    [regexp.Match(submatches: [Some(prefix)], ..)] -> files(prefix, cursor, cwd)
    // Empty captured strings are omitted by gleam_regexp's scanner.
    [regexp.Match(..)] -> files("", cursor, cwd)
    _ -> {
      let choices = case regexp.scan(named, before) {
        [regexp.Match(content:, ..)] -> {
          let prefix = string.drop_start(content, 1)
          packages
          |> list.filter(string.starts_with(_, prefix))
          |> list.take(30)
          |> list.map(fn(name) {
            Completion(
              "@" <> name,
              "hub package",
              "@" <> name,
              cursor - string.length(content),
              cursor,
            )
          })
        }
        _ -> []
      }
      promise.resolve(choices)
    }
  }
}

pub fn files(prefix, cursor, cwd) {
  let parts = string.split(prefix, "/") |> list.reverse
  let #(directory, partial) = case parts {
    [] -> #("", "")
    [partial] -> #("", partial)
    [partial, ..rest] -> #(
      list.reverse(rest) |> string.join("/") |> string.append("/"),
      partial,
    )
  }
  let path = case filepath.is_absolute(directory) {
    True -> directory
    False -> filepath.join(cwd, directory)
  }
  use entries <- promise.map(fs.readdir_with_file_types(path))
  entries
  |> result.unwrap([])
  |> list.filter(fn(entry) {
    let name = fs.name(entry)
    string.starts_with(name, partial)
    && { !string.starts_with(name, ".") || string.starts_with(partial, ".") }
    && { partial != "" || { name != "node_modules" && name != "build" } }
  })
  |> list.sort(fn(a, b) {
    case fs.is_directory(a), fs.is_directory(b) {
      True, False -> order.Lt
      False, True -> order.Gt
      _, _ -> string.compare(fs.name(a), fs.name(b))
    }
  })
  |> list.take(30)
  |> list.map(fn(entry) {
    let directory_entry = fs.is_directory(entry)
    let label =
      directory
      <> fs.name(entry)
      <> case directory_entry {
        True -> "/"
        False -> ""
      }
    Completion(
      label,
      case directory_entry {
        True -> "directory"
        False -> "file"
      },
      label,
      cursor - string.length(prefix),
      cursor,
    )
  })
}

pub fn hints(value: String, hints: List(#(String, String))) {
  hints
  |> list.filter(fn(hint) { string.contains(hint.0, value) })
  |> list.take(30)
  |> list.map(fn(hint) {
    Completion(hint.0, hint.1, hint.0, 0, string.length(value))
  })
}

pub fn apply(source, choice: Completion) {
  let prefix = string.slice(source, 0, choice.from) <> choice.insert
  // Use grapheme slicing on both sides. The pinned stdlib's JS drop_start
  // mixes UTF-8 byte counts with native UTF-16 slicing for non-ASCII prefixes.
  #(prefix <> string.slice(source, choice.to, string.length(source)), prefix)
}
