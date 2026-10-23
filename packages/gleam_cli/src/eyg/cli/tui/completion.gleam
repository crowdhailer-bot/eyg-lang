//// Completion of hub packages after `@` and of files in imports. Offsets count
//// graphemes, as the editor does.

import filepath
import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/regexp
import gleam/result
import gleam/string
import simplifile

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
      choices
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
  simplifile.read_directory(path)
  |> result.unwrap([])
  |> list.map(fn(name) {
    #(name, simplifile.is_directory(filepath.join(path, name)) == Ok(True))
  })
  |> list.filter(fn(entry) {
    let #(name, _) = entry
    string.starts_with(name, partial)
    && { !string.starts_with(name, ".") || string.starts_with(partial, ".") }
    && { partial != "" || { name != "node_modules" && name != "build" } }
  })
  |> list.sort(fn(a, b) {
    case a.1, b.1 {
      True, False -> order.Lt
      False, True -> order.Gt
      _, _ -> string.compare(a.0, b.0)
    }
  })
  |> list.take(30)
  |> list.map(fn(entry) {
    let #(name, directory_entry) = entry
    let label =
      directory
      <> name
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

pub fn apply(source, choice: Completion) {
  let prefix = string.slice(source, 0, choice.from) <> choice.insert
  // Use grapheme slicing on both sides. The pinned stdlib's JS drop_start
  // mixes UTF-8 byte counts with native UTF-16 slicing for non-ASCII prefixes.
  #(prefix <> string.slice(source, choice.to, string.length(source)), prefix)
}
