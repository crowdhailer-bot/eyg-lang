//// A type-safe implementation of evaluating questions using the Jev mode from typesafe.ai.

import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import midas/continuation.{type Continuation as K}
import midas/effect
import ogre/origin

pub type Client(t) {
  Client(
    origin: origin.Origin,
    token: String,
    model: String,
    fetch: effect.Fetch(t),
  )
}

pub type Failure {
  Unauthenticated(message: String)
  BadRequest(message: String)
  TooManyTokens
  InvalidRequest(problems: List(Problem))
  RateLimited(retry_after: Option(Int))
  Overloaded(retry_after: Option(Int))
  UnexpectedResponse(status: Int, body: BitArray)
  UnableToDecode(reason: json.DecodeError)
  UnableToFetch(reason: effect.FetchError)
}

pub type Problem {
  Problem(location: List(String), message: String)
}

/// Evaluate all questions against the same state with POST /v1/systemone.
/// The bundle determines the type of `Evaluation.answer`.
pub fn evaluate(
  client: Client(t),
  state: String,
  bundle: Bundle(a),
) -> K(t, Result(Evaluation(a), Failure)) {
  let Client(origin:, token:, model:, fetch:) = client
  let #(questions, decoder) = bundle
  let body =
    json.to_string(request_encode(model, json.string(state), questions))
  let request =
    origin.to_request(origin)
    |> request.set_method(http.Post)
    |> request.set_path("/v1/systemone")
    |> request.set_header("content-type", "application/json")
    |> request.set_header("authorization", "Bearer " <> token)
    |> request.set_body(<<body:utf8>>)
  send(fetch, request, evaluation_decoder(decoder))
}

fn send(fetch, request, decoder) {
  use response <- continuation.then(fetch(request))
  case response {
    Ok(response.Response(status: 200, body:, ..)) ->
      json.parse_bits(body, decoder) |> result.map_error(UnableToDecode)
    Ok(response) -> Error(failure(response))
    Error(reason) -> Error(UnableToFetch(reason))
  }
  |> continuation.return
}

fn failure(response: response.Response(BitArray)) -> Failure {
  let response.Response(status:, body:, ..) = response
  let retry_after =
    response.get_header(response, "retry-after")
    |> result.try(int.parse)
    |> result.try(fn(seconds) {
      case seconds >= 0 {
        True -> Ok(seconds)
        False -> Error(Nil)
      }
    })
    |> option.from_result
  case status {
    400 ->
      case
        json.parse_bits(
          body,
          decode.at(["detail", "error_type"], decode.string),
        )
      {
        Ok("max_tokens_exceeded") -> TooManyTokens
        _ ->
          decode_failure(
            status,
            body,
            decode.map(message_decoder(), BadRequest),
          )
      }
    401 | 403 ->
      decode_failure(
        status,
        body,
        decode.map(message_decoder(), Unauthenticated),
      )
    422 ->
      decode_failure(
        status,
        body,
        decode.map(
          decode.at(["detail"], decode.list(problem_decoder())),
          InvalidRequest,
        ),
      )
    429 -> RateLimited(retry_after)
    529 -> Overloaded(retry_after)
    _ -> UnexpectedResponse(status:, body:)
  }
}

fn decode_failure(status, body, decoder) {
  json.parse_bits(body, decoder)
  |> result.unwrap(UnexpectedResponse(status:, body:))
}

fn message_decoder() {
  decode.one_of(decode.at(["detail", "message"], decode.string), [
    decode.at(["detail"], decode.string),
  ])
}

fn problem_decoder() {
  let segment =
    decode.one_of(decode.string, [decode.map(decode.int, int.to_string)])
  use location <- decode.field("loc", decode.list(segment))
  use message <- decode.field("msg", decode.string)
  decode.success(Problem(location:, message:))
}

fn request_encode(model, state, questions) {
  json.object([
    #("state", state),
    #("model", json.string(model)),
    #("questions", json.object(list.map(questions, question_entry))),
  ])
}

fn question_entry(entry) {
  let #(key, question) = entry
  #(key, question_encode(question))
}

fn question_encode(question: Question) -> Json {
  case question {
    Noul(instructions:, true_criteria:, false_criteria:) ->
      noul_encode(instructions, true_criteria, false_criteria)
    Choice(instructions:, options:) -> choice_encode(instructions, options)
    Score(instructions:, levels:) -> score_encode(instructions, levels)
  }
}

fn noul_encode(instructions, true_criteria, false_criteria) {
  let criteria = case true_criteria, false_criteria {
    None, None -> []
    Some(t), None -> [#("criteria", json.object([#("true", t)]))]
    None, Some(f) -> [#("criteria", json.object([#("true", f)]))]
    Some(t), Some(f) -> [
      #("criteria", json.object([#("true", t), #("false", f)])),
    ]
  }
  json.object([
    #("type", json.string("noul")),
    #("instructions", instructions),
    ..criteria
  ])
}

fn choice_encode(instructions, options) {
  json.object([
    #("type", json.string("choice")),
    #("instructions", instructions),
    #("criteria", json.object(options)),
  ])
}

fn score_encode(instructions, levels) {
  json.object([
    #("type", json.string("score")),
    #("instructions", instructions),
    #("criteria", json.preprocessed_array(levels)),
  ])
}

pub type Evaluation(t) {
  Evaluation(model: String, answer: t, usage: Usage)
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

fn usage_decoder() {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Usage(input_tokens:, output_tokens:))
}

fn evaluation_decoder(answer_decoder: Decoder(t)) -> Decoder(Evaluation(t)) {
  use model <- decode.field("model", decode.string)
  use answer <- decode.field("answers", answer_decoder)
  use usage <- decode.field("usage", usage_decoder())
  decode.success(Evaluation(model:, answer:, usage:))
}

type Bundle(t) =
  #(List(#(String, Question)), Decoder(t))

/// Add a question to a bundle. The callback runs both to collect questions
/// (using a placeholder answer) and to decode answers. Keep the remaining
/// questions independent of earlier answers; all are sent in one request.
pub fn and(
  question: #(Question, Decoder(a), a),
  then: fn(a) -> Bundle(t),
) -> Bundle(t) {
  let #(q, decoder, zero) = question

  let #(questions, _) = then(zero)
  let id = int.to_string(list.length(questions))
  let decoder = decode.field(id, decoder, fn(answer) { then(answer).1 })
  #([#(id, q), ..questions], decoder)
}

/// Finish a bundle with the value to return as `Evaluation.answer`.
pub fn return(x: t) -> Bundle(t) {
  #([], decode.success(x))
}

pub type Question {
  Noul(
    instructions: Json,
    true_criteria: Option(Json),
    false_criteria: Option(Json),
  )
  Choice(instructions: Json, options: List(#(String, Json)))
  Score(instructions: Json, levels: List(Json))
}

/// Ask the model is something is true or false returning a float between 0 and 1
pub fn noul(instructions: String, true, false) {
  #(
    Noul(
      json.string(instructions),
      option.map(true, json.string),
      option.map(false, json.string),
    ),
    decode.at(["noul"], number()),
    0.0,
  )
}

/// Associate an API label with an application value and a description.
pub fn option(label: String, value, rubric: String) {
  #(label, #(value, json.string(rubric)))
}

pub fn choice(instructions: String, options, zero) {
  let #(rubrics, values) =
    list.map(options, fn(option) {
      let #(label, #(value, rubric)) = option
      #(#(label, rubric), #(label, value))
    })
    |> list.unzip
  #(
    Choice(instructions: json.string(instructions), options: rubrics),
    {
      let choice_decoder = {
        use choice <- decode.then(decode.string)
        case list.key_find(values, choice) {
          Ok(value) -> decode.success(value)
          Error(Nil) -> decode.failure(zero, "choice")
        }
      }
      use choice <- decode.field("choice", choice_decoder)
      use probabilities <- decode.field(
        "probabilities",
        decode.dict(choice_decoder, number()),
      )
      use confidence <- decode.field("confidence", number())
      decode.success(#(choice, probabilities, confidence))
    },
    #(zero, dict.new(), 0.0),
  )
}

/// Returns #(score, legend, probabilities, confidence). Supply 2–10 levels
/// ordered lowest to highest. Legend and probability keys are index strings.
pub fn score(instructions: String, levels: List(String)) {
  let instructions = json.string(instructions)
  let levels = list.map(levels, json.string)
  #(
    Score(instructions:, levels:),
    {
      use score <- decode.field("score", number())
      use legend <- decode.field(
        "legend",
        decode.dict(decode.string, decode.string),
      )
      use probabilities <- decode.field(
        "probabilities",
        decode.dict(decode.string, number()),
      )
      use confidence <- decode.field("confidence", number())
      decode.success(#(score, legend, probabilities, confidence))
    },
    #(0.0, dict.new(), dict.new(), 0.0),
  )
}

fn number() {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub type Model {
  Model(name: String, description: String, release_date: String)
}

/// Discover available models with GET /v1/models using the same fetch effect.
pub fn list_models(client: Client(t)) -> K(t, Result(List(Model), Failure)) {
  let request =
    origin.to_request(client.origin)
    |> request.set_path("/v1/models")
    |> request.set_header("authorization", "Bearer " <> client.token)
    |> request.set_body(<<>>)
  let decoder =
    decode.at(
      ["models"],
      decode.list({
        use name <- decode.field("name", decode.string)
        use description <- decode.field("description", decode.string)
        use release_date <- decode.field("release_date", decode.string)
        decode.success(Model(name:, description:, release_date:))
      }),
    )
  send(client.fetch, request, decoder)
}
