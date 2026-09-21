//// Jev chooses between options and cannot generate text.
//// Names, labels and literals are offered from those in the task, the program
//// and a small list of common names.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/string
import morph/editable as e

pub type Vocabulary {
  Vocabulary(
    names: List(String),
    labels: List(String),
    tags: List(String),
    strings: List(String),
    integers: List(Int),
    /// Groups of labels written together, as in `{a, b}`, offered as one record.
    records: List(List(String)),
  )
}

const common_names = [
  "x", "item", "value", "acc", "result", "response", "request", "_",
]

const common_tags = ["Ok", "Error", "True", "False"]

const common_integers = [0, 1]

pub fn from_task(task: String) -> Vocabulary {
  // An empty capture is reported as `None` so `""` is looked for separately.
  let quoted = matches("\"([^\"]*)\"", task)
  let quoted = case string.contains(task, "\"\"") {
    True -> list.append(quoted, [""])
    False -> quoted
  }
  let code = matches("`([^`]+)`", task)
  let code_words = list.flat_map(code, words)
  let identifiers =
    list.filter(code_words, is_name)
    |> list.append(
      list.filter(words(task), fn(word) {
        is_name(word) && string.contains(word, "_")
      }),
    )
  let tags =
    list.append(
      list.filter(code_words, is_tag),
      list.filter(words(task), is_common_tag),
    )
  let integers =
    matches("(?<![\\w/\"])(-?[0-9]+)(?![\\w/\"])", task)
    |> list.filter_map(int.parse)
  let records =
    list.filter_map(code, fn(code) {
      case string.starts_with(code, "{") {
        True ->
          case list.filter(words(code), is_name) {
            [] -> Error(Nil)
            labels -> Ok(labels)
          }
        False -> Error(Nil)
      }
    })
  Vocabulary(
    names: identifiers,
    labels: identifiers,
    tags:,
    strings: quoted,
    integers:,
    records:,
  )
}

/// Names and literals already written in the program can be written again.
pub fn from_program(source: e.Expression) -> Vocabulary {
  let found = collect(source, Vocabulary([], [], [], [], [], []))
  Vocabulary(
    names: list.reverse(found.names),
    labels: list.reverse(found.labels),
    tags: list.reverse(found.tags),
    strings: list.reverse(found.strings),
    integers: list.reverse(found.integers),
    records: [],
  )
}

pub fn defaults() -> Vocabulary {
  Vocabulary(
    names: common_names,
    labels: [],
    tags: common_tags,
    strings: [],
    integers: common_integers,
    records: [],
  )
}

/// Combine vocabularies keeping the first occurrence of each entry.
pub fn merge(vocabularies: List(Vocabulary)) -> Vocabulary {
  Vocabulary(
    names: all(vocabularies, fn(v: Vocabulary) { v.names }),
    labels: all(vocabularies, fn(v: Vocabulary) { v.labels }),
    tags: all(vocabularies, fn(v: Vocabulary) { v.tags }),
    strings: all(vocabularies, fn(v: Vocabulary) { v.strings }),
    integers: all(vocabularies, fn(v: Vocabulary) { v.integers }),
    records: all(vocabularies, fn(v: Vocabulary) { v.records }),
  )
}

fn all(vocabularies, get) {
  list.flat_map(vocabularies, get) |> list.unique
}

pub fn for_task(task, source) {
  merge([from_task(task), from_program(source), defaults()])
}

fn matches(pattern, text) {
  let assert Ok(re) = regexp.from_string(pattern)
  regexp.scan(re, text)
  |> list.filter_map(fn(match) {
    case match.submatches {
      [Some(value), ..] -> Ok(value)
      _ -> Error(Nil)
    }
  })
}

fn words(text) {
  let assert Ok(re) = regexp.from_string("[A-Za-z_][A-Za-z0-9_]*")
  regexp.scan(re, text) |> list.map(fn(match) { match.content })
}

fn is_name(text) {
  let assert Ok(re) = regexp.from_string("^[a-z_][a-z0-9_]*$")
  regexp.check(re, text) && !list.contains(keywords, text)
}

const keywords = ["let", "match", "perform", "handle", "deep", "import"]

fn is_tag(text) {
  let assert Ok(re) = regexp.from_string("^[A-Z][a-zA-Z0-9]*$")
  regexp.check(re, text)
}

fn is_common_tag(text) {
  list.contains(common_tags, text)
}

fn collect(exp, acc: Vocabulary) -> Vocabulary {
  case exp {
    e.Block(assigns, then, _) -> {
      let acc =
        list.fold(assigns, acc, fn(acc, assign) {
          let #(pattern, value) = assign
          collect(value, pattern_names(pattern, acc))
        })
      collect(then, acc)
    }
    e.Call(func, args) ->
      list.fold(args, collect(func, acc), fn(acc, arg) { collect(arg, acc) })
    e.Function(params, body) ->
      collect(
        body,
        list.fold(params, acc, fn(acc, p) { pattern_names(p, acc) }),
      )
    e.List(items, tail) -> {
      let acc = list.fold(items, acc, fn(acc, item) { collect(item, acc) })
      case tail {
        Some(tail) -> collect(tail, acc)
        None -> acc
      }
    }
    e.Record(fields, original) -> {
      let acc =
        list.fold(fields, acc, fn(acc, field) {
          let #(label, value) = field
          collect(value, add_label(acc, label))
        })
      case original {
        Some(original) -> collect(original, acc)
        None -> acc
      }
    }
    e.Select(from, label) -> collect(from, add_label(acc, label))
    e.Case(top, matches, otherwise) -> {
      let acc =
        list.fold(matches, collect(top, acc), fn(acc, match) {
          let #(label, branch) = match
          collect(branch, Vocabulary(..acc, tags: [label, ..acc.tags]))
        })
      case otherwise {
        Some(otherwise) -> collect(otherwise, acc)
        None -> acc
      }
    }
    e.Tag(label) -> Vocabulary(..acc, tags: [label, ..acc.tags])
    e.String(value) -> Vocabulary(..acc, strings: [value, ..acc.strings])
    e.Integer(value) -> Vocabulary(..acc, integers: [value, ..acc.integers])
    _ -> acc
  }
}

fn add_label(acc: Vocabulary, label) {
  Vocabulary(..acc, labels: [label, ..acc.labels])
}

fn pattern_names(pattern, acc: Vocabulary) {
  case pattern {
    e.Bind("$") -> acc
    e.Bind(name) -> Vocabulary(..acc, names: [name, ..acc.names])
    e.Destructure(fields) ->
      list.fold(fields, acc, fn(acc, field) {
        let #(label, name) = field
        Vocabulary(..acc, names: [name, ..acc.names], labels: [
          label,
          ..acc.labels
        ])
      })
  }
}
