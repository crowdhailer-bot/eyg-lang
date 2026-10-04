//// Decode the overlay configuration returned by an EYG program.
////
//// The configuration is a record `{llm, policy, context}`.
//// Errors name the path of the field at fault and never print values,
//// as configuration values often contain secrets such as API keys.

import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/policy

pub type Config(value) {
  Config(llm: provider.Llm, policy: policy.Policy(value), context: value)
}

/// The model used when the config names only a provider.
pub const default_model = "glm-5.3:cloud"

/// Decode the config, `labels` are the effects available on the platform.
pub fn decode(
  value: v.Value(m, c),
  labels: List(String),
) -> Result(Config(v.Value(m, c)), String) {
  use llm <- result.try(field(value, [], "llm", llm))
  use policy <- result.try(
    field(value, [], "policy", fn(value, _path) { policy.decode(value, labels) }),
  )
  use context <- result.try(
    field(value, [], "context", fn(value, _) { Ok(value) }),
  )
  Ok(Config(llm:, policy:, context:))
}

/// The llm is either `{provider, model}` or a bare provider, which uses the default model.
pub fn llm(value: v.Value(m, c), path: List(String)) {
  case value {
    v.Record(_) -> {
      use provider <- result.try(field(value, path, "provider", provider))
      use model <- result.try(field(value, path, "model", string))
      Ok(provider.Llm(provider:, model:))
    }
    _ ->
      provider(value, path)
      |> result.map(provider.Llm(provider: _, model: default_model))
  }
}

const providers = "Ollama({origin, api_key})"

fn provider(value: v.Value(m, c), path) {
  case value {
    v.Tagged("Ollama", inner) -> {
      let path = ["Ollama", ..path]
      use origin <- result.try(field(inner, path, "origin", origin))
      use api_key <- result.try(field(inner, path, "api_key", optional(string)))
      Ok(provider.Ollama(ollama.Config(origin:, api_key:)))
    }
    v.Tagged(label, _) ->
      Error(
        "unknown llm provider `"
        <> label
        <> "` at "
        <> show_path(path)
        <> ", supported providers are: "
        <> providers,
      )
    _ -> expected(path, "a provider such as " <> providers, value)
  }
}

fn origin(value, path) {
  use raw <- result.try(string(value, path))
  case origin.from_string(raw) {
    Ok(origin) ->
      case string.contains(drop_scheme(raw), "/") {
        False -> Ok(origin)
        True ->
          Error(
            show_path(path)
            <> " should be an origin, scheme host and optional port, without a path",
          )
      }
    Error(_) ->
      Error(
        show_path(path) <> " should be an origin such as \"https://ollama.com\"",
      )
  }
}

fn drop_scheme(raw) {
  case string.split_once(raw, "://") {
    Ok(#(_, rest)) -> rest
    Error(Nil) -> raw
  }
}

/// Decode a field of a record, the path is held innermost first.
pub fn field(
  value: v.Value(m, c),
  path: List(String),
  key: String,
  inner: fn(v.Value(m, c), List(String)) -> Result(t, String),
) -> Result(t, String) {
  case value {
    v.Record(fields) ->
      case dict.get(fields, key) {
        Ok(value) -> inner(value, [key, ..path])
        Error(Nil) -> Error("missing field " <> show_path([key, ..path]))
      }
    _ -> expected(path, "a record with field `" <> key <> "`", value)
  }
}

pub fn string(value: v.Value(m, c), path) -> Result(String, String) {
  case value {
    v.String(value) -> Ok(value)
    _ -> expected(path, "a String", value)
  }
}

pub fn optional(inner) {
  fn(value: v.Value(m, c), path) {
    case value {
      v.Tagged("Some", value) -> result.map(inner(value, path), Some)
      v.Tagged("None", _) -> Ok(None)
      _ -> expected(path, "Some(value) or None({})", value)
    }
  }
}

fn expected(
  path: List(String),
  expected: String,
  value: v.Value(m, c),
) -> Result(a, String) {
  Error(
    show_path(path)
    <> " should be "
    <> expected
    <> " but is "
    <> describe_kind(value),
  )
}

fn show_path(path) {
  case path {
    [] -> "the config"
    _ -> "`" <> string.join(list.reverse(path), ".") <> "`"
  }
}

/// Describe a value without showing it.
pub fn describe_kind(value: v.Value(m, c)) -> String {
  case value {
    v.Binary(..) -> "a Binary"
    v.Integer(..) -> "an Integer"
    v.String(..) -> "a String"
    v.LinkedList(..) -> "a List"
    v.Record(fields) ->
      case dict.keys(fields) |> list.sort(string.compare) {
        [] -> "an empty record"
        keys -> "a record with fields " <> string.join(keys, ", ")
      }
    v.Tagged(label, _) -> "tagged " <> label
    v.Closure(..) | v.Partial(..) -> "a function"
  }
}
