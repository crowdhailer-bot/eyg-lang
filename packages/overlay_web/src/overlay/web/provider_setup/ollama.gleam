import gleam/option.{Some}
import overlay/llm/provider
import overlay/llm/provider/ollama

pub const id = "ollama"

pub const label = "Ollama Cloud"

pub const token_url = "https://ollama.com/settings/keys"

pub fn default_model() {
  "kimi-k2.6"
}

pub fn models() {
  [
    #("kimi-k2.6", "Kimi K2.6"),
    #("kimi-k3", "Kimi K3"),
    #("glm-5.3", "GLM 5.3"),
    #("gpt-oss:120b", "GPT-OSS 120B"),
    #("mistral-large-3:675b", "Mistral Large 3"),
  ]
}

pub fn make_provider(api_key, origin) {
  provider.Ollama(ollama.Config(origin: origin, api_key: Some(api_key)))
}
