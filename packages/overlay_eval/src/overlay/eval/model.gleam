//// The model a session asks for completions.
////
//// A provider is Overlay's own provider configuration and a transport that
//// carries its requests. The network is the usual transport, cassettes record
//// and replay exchanges so a run can be graded again without a model.
//// Switching provider or model changes nothing else about a session.

import gleam/fetch
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}
import gleam/result
import overlay/eval/agent
import overlay/llm/provider
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import pal/system

pub type Model {
  // A provider, its requests are sent with the transport.
  Provider(llm: provider.Llm, transport: Transport)
  // A scripted agent, it answers in the Ollama format.
  Scripted(agent.Agent)
}

pub type Transport =
  fn(Request(BitArray)) ->
    Promise(Result(Response(system.Reader), fetch.FetchError))

/// Send requests over the network and stream the responses.
pub fn network() -> Transport {
  fn(request) {
    use result <- promise.map(fetch.send_bits(request))
    use response <- result.try(result)
    use body <- result.map(fetch.stream_body(response))
    Response(..response, body: fn() { fetch.read_chunk(body) })
  }
}

/// A model on Ollama Cloud.
pub fn ollama_cloud(model: String, api_key: String) -> Model {
  Provider(
    provider.Llm(provider.Ollama(ollama.cloud(api_key)), model),
    network(),
  )
}

/// A model on an Ollama server on this machine.
pub fn ollama_local(model: String) -> Model {
  Provider(provider.Llm(provider.Ollama(ollama.local()), model), network())
}

/// A model on La Plateforme from Mistral.
pub fn mistral(model: String, api_key: String) -> Model {
  Provider(
    provider.Llm(provider.Mistral(mistral.Config(api_key:)), model),
    network(),
  )
}

/// A short name for the model, for reports.
pub fn describe(model: Model) -> String {
  case model {
    Scripted(_) -> "scripted"
    Provider(llm: provider.Llm(provider: provider.Ollama(config), model:), ..) ->
      case config.api_key {
        Some(_) -> "ollama/" <> model
        _ -> "ollama-local/" <> model
      }
    Provider(llm: provider.Llm(provider: provider.Mistral(_), model:), ..) ->
      "mistral/" <> model
  }
}
