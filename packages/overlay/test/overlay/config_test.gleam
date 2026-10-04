import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import ogre/origin
import overlay/config
import overlay/llm/provider
import overlay/llm/provider/ollama

fn record(fields) -> v.Value(Nil, Nil) {
  v.Record(dict.from_list(fields))
}

fn ollama(origin, api_key) {
  v.Tagged(
    "Ollama",
    record([#("origin", v.String(origin)), #("api_key", api_key)]),
  )
}

fn config(llm) {
  record([
    #("llm", llm),
    #("policy", record([])),
    #("context", record([])),
  ])
}

const secret = "sk-secret"

pub fn llm_with_model_test() {
  let llm =
    record([
      #(
        "provider",
        ollama("https://ollama.com", v.Tagged("Some", v.String("k"))),
      ),
      #("model", v.String("gpt-oss:20b")),
    ])
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm
    == provider.Llm(
      provider.Ollama(ollama.Config(origin.https("ollama.com"), Some("k"))),
      "gpt-oss:20b",
    )
}

pub fn bare_provider_uses_default_model_test() {
  let llm = ollama("http://localhost:11434", v.Tagged("None", record([])))
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm.model == config.default_model
  let assert provider.Ollama(ollama.Config(api_key: None, ..)) = llm.provider
}

pub fn unknown_provider_does_not_show_secret_test() {
  let llm = v.Tagged("Codex", record([#("access_token", v.String(secret))]))
  let assert Error(reason) = config.decode(config(llm), [])
  assert reason
    == "unknown llm provider `Codex` at `llm`, supported providers are: Ollama({origin, api_key})"
}

pub fn api_key_not_optional_does_not_show_secret_test() {
  let llm = ollama("https://ollama.com", v.String(secret))
  let assert Error(reason) = config.decode(config(llm), [])
  assert !string.contains(reason, secret)
  assert reason
    == "`llm.Ollama.api_key` should be Some(value) or None({}) but is a String"
}

pub fn missing_field_test() {
  let assert Error(reason) = config.decode(record([]), [])
  assert reason == "missing field `llm`"
}

pub fn origin_with_path_test() {
  let llm = ollama("https://ollama.com/v1", v.Tagged("None", record([])))
  let assert Error(reason) = config.decode(config(llm), [])
  assert reason
    == "`llm.Ollama.origin` should be an origin, scheme host and optional port, without a path"
}

pub fn config_not_record_test() {
  let assert Error(reason) = config.decode(v.Integer(1), [])
  assert reason
    == "the config should be a record with field `llm` but is an Integer"
}
