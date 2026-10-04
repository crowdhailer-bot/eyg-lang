import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import ogre/origin
import overlay/config
import overlay/llm/provider
import overlay/llm/provider/bedrock
import overlay/llm/provider/codex
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import overlay/llm/provider/openai
import overlay/llm/sigv4

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
  let llm = v.Tagged("Gemini", record([#("api_key", v.String(secret))]))
  let assert Error(reason) = config.decode(config(llm), [])
  assert reason
    == "unknown llm provider `Gemini` at `llm`, supported providers are: Ollama({origin, api_key}), Mistral({api_key}), OpenAI({origin, api_key}), Codex({access_token, account_id}), Bedrock({region, access_key_id, secret_access_key, session_token})"
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

pub fn mistral_test() {
  let llm =
    record([
      #("provider", v.Tagged("Mistral", record([#("api_key", v.String("k"))]))),
      #("model", v.String("mistral-small-latest")),
    ])
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm
    == provider.Llm(
      provider.Mistral(mistral.Config("k")),
      "mistral-small-latest",
    )
}

pub fn openai_test() {
  let llm =
    record([
      #(
        "provider",
        v.Tagged(
          "OpenAI",
          record([
            #("origin", v.String("https://openrouter.ai")),
            #("api_key", v.Tagged("Some", v.String("k"))),
            #("path", v.String("/api/v1/chat/completions")),
            #(
              "headers",
              v.LinkedList([
                record([
                  #("key", v.String("x-title")),
                  #("value", v.String("o")),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      #("model", v.String("openai/gpt-5")),
    ])
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm.provider
    == provider.OpenAI(
      openai.Config(
        origin: origin.https("openrouter.ai"),
        path: "/api/v1/chat/completions",
        api_key: Some("k"),
        headers: [#("x-title", "o")],
      ),
    )
}

pub fn openai_defaults_test() {
  let llm =
    v.Tagged(
      "OpenAI",
      record([
        #("origin", v.String("http://localhost:8080")),
        #("api_key", v.Tagged("None", record([]))),
      ]),
    )
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  let assert provider.OpenAI(openai.Config(path:, headers: [], ..)) =
    llm.provider
  assert path == "/v1/chat/completions"
}

pub fn codex_test() {
  let llm =
    record([
      #(
        "provider",
        v.Tagged(
          "Codex",
          record([
            #("access_token", v.String("token")),
            #("account_id", v.String("account")),
          ]),
        ),
      ),
      #("model", v.String("gpt-5.5")),
    ])
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm.provider == provider.Codex(codex.Config("token", "account"))
}

pub fn bedrock_test() {
  let llm =
    record([
      #(
        "provider",
        v.Tagged(
          "Bedrock",
          record([
            #("region", v.String("eu-west-1")),
            #("access_key_id", v.String("AKID")),
            #("secret_access_key", v.String("secret")),
          ]),
        ),
      ),
      #("model", v.String("anthropic.claude")),
    ])
  let assert Ok(config.Config(llm:, ..)) = config.decode(config(llm), [])
  assert llm.provider
    == provider.Bedrock(bedrock.Config(
      "eu-west-1",
      sigv4.Credentials("AKID", "secret", None),
    ))
}
