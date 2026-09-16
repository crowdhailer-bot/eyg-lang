//// Inline the files of a bundle as data URLs.
////
//// A preview has no network access, the entrypoint must carry every file it
//// uses. References resolve relative to the file they are in, as they would
//// if the bundle were served from a directory.

import eyg/hub/artifact as rules
import gleam/bit_array
import gleam/list
import gleam/result.{try}
import gleam/string
import gleam/uri
import overlay/web/artifact.{type Bundle, type File}
import overlay/web/artifact/css

/// Find the file a reference in `from` refers to.
/// Returns the file and any fragment, e.g. `#icon` for SVG sprites.
///
/// Resolution follows URLs with a hierarchical path, queries are ignored.
/// Anything with a scheme or host is external to the bundle.
pub fn resolve(
  bundle: Bundle,
  reference: String,
  from: String,
) -> Result(#(File, String), String) {
  // URL parsing ignores surrounding whitespace and treats backslash as slash.
  let location = string.trim(reference) |> string.replace("\\", "/")
  let #(location, fragment) = split(location, "#")
  let #(path, _query) = split(location, "?")
  case has_scheme(path) || string.starts_with(path, "//") {
    True -> Error("External resource must be bundled: " <> reference)
    False -> {
      let segments = case path {
        "/" <> path -> string.split(path, "/")
        _ -> list.append(directory(from), string.split(path, "/"))
      }
      let path =
        normalize(segments, [])
        |> string.join("/")
      let path = uri.percent_decode(path) |> result.unwrap(path)
      case artifact.file(bundle, path) {
        Ok(file) -> Ok(#(file, fragment))
        Error(Nil) -> Error("Missing bundle file: " <> path)
      }
    }
  }
}

fn split(value, separator) {
  case string.split_once(value, separator) {
    Ok(#(before, after)) -> #(before, separator <> after)
    Error(Nil) -> #(value, "")
  }
}

fn has_scheme(path) {
  case string.split_once(path, ":") {
    Ok(#(scheme, _)) ->
      case string.to_graphemes(scheme) {
        [first, ..rest] ->
          is_letter(first)
          && list.all(rest, fn(c) {
            is_letter(c) || is_digit(c) || c == "+" || c == "-" || c == "."
          })
        [] -> False
      }
    Error(Nil) -> False
  }
}

fn is_letter(c) {
  string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", c)
}

fn is_digit(c) {
  string.contains("0123456789", c)
}

fn directory(path) {
  case list.reverse(string.split(path, "/")) {
    [_file, ..directories] -> list.reverse(directories)
    [] -> []
  }
}

// Remove dot segments, `..` beyond the root stays at the root.
fn normalize(segments, acc) {
  case segments {
    [] -> list.reverse(acc)
    [".", ..rest] -> normalize(rest, acc)
    ["..", ..rest] -> normalize(rest, list.drop(acc, 1))
    [segment, ..rest] -> normalize(rest, [segment, ..acc])
  }
}

/// The location to use for a resource, data URLs and fragments stay in place.
pub fn asset(
  bundle: Bundle,
  reference: String,
  from: String,
) -> Result(String, String) {
  case reference {
    "data:" <> _ | "#" <> _ -> Ok(reference)
    _ -> {
      use #(file, fragment) <- try(resolve(bundle, reference, from))
      use url <- try(data_url(file))
      Ok(url <> fragment)
    }
  }
}

pub fn data_url(file: File) -> Result(String, String) {
  case rules.valid_media_type(file.media_type) {
    True ->
      Ok(
        "data:"
        <> file.media_type
        <> ";base64,"
        <> bit_array.base64_encode(file.content, True),
      )
    False -> Error("Invalid media type for " <> file.path)
  }
}

pub fn text_data_url(media_type: String, text: String) -> String {
  "data:"
  <> media_type
  <> ";charset=utf-8;base64,"
  <> bit_array.base64_encode(bit_array.from_string(text), True)
}

/// Rewrite a stylesheet found in `from` so its assets and imports are inline.
pub fn stylesheet(
  bundle: Bundle,
  source: String,
  from: String,
) -> Result(String, String) {
  do_stylesheet(bundle, source, from, [])
}

fn do_stylesheet(bundle, source, from, ancestors) {
  use <- guard(list.contains(ancestors, from), "Circular CSS import: " <> from)
  let ancestors = [from, ..ancestors]
  css.rewrite(source, fn(reference) {
    case reference {
      css.Url(location) -> asset(bundle, location, from)
      css.Import(location) -> {
        use #(file, _fragment) <- try(resolve(bundle, location, from))
        use text <- try(text(file))
        use source <- try(do_stylesheet(bundle, text, file.path, ancestors))
        Ok(text_data_url("text/css", source))
      }
    }
  })
}

pub fn text(file: File) -> Result(String, String) {
  bit_array.to_string(file.content)
  |> result.replace_error(file.path <> " is not UTF-8 text")
}

fn guard(condition, reason, then) {
  case condition {
    True -> Error(reason)
    False -> then()
  }
}
