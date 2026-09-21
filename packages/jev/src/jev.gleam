//// Client for the TypeSafe System One API, the service running the Jev model.
//// Jev evaluates a state against named questions and answers each one with
//// probabilities rather than generated text.
////
//// Functions build `Operation`s and decode `Response`s without doing any IO,
//// send them with whichever HTTP client the runtime provides.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/http/request
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import ogre/operation.{type Operation}
import ogre/origin.{type Origin}

/// The most recent stable release of Jev.
pub const latest = "jev-latest"

/// The most recent release of Jev, official or not.
pub const preview = "jev-preview"

/// The API accepts at most this many options in a single choice question.
pub const max_choice_options = 255

/// The API accepts at most this many levels in a single score question.
pub const max_score_levels = 10

pub fn origin() -> Origin {
  origin.https("api.typesafe.ai")
}

/// Instructions and criteria are strings, objects or arrays.
/// Structured values can hold data that the text refers to by name.
pub type Question {
  Noul(instructions: Json, criteria: Option(NoulCriteria))
  Choice(instructions: Json, criteria: List(#(String, Option(Json))))
  Score(instructions: Json, criteria: List(Json))
}

/// Descriptions of what yes and no mean for a noul question.
pub type NoulCriteria {
  NoulCriteria(true: Json, false: Json)
}

pub fn noul(instructions: String) -> Question {
  Noul(json.string(instructions), None)
}

/// A choice between named options, each with a description.
pub fn choice(
  instructions: String,
  options: List(#(String, String)),
) -> Question {
  let criteria =
    list.map(options, fn(option) {
      let #(key, description) = option
      #(key, Some(json.string(description)))
    })
  Choice(json.string(instructions), criteria)
}

/// Rate against levels, ordered from lowest to highest.
pub fn score(instructions: String, levels: List(String)) -> Question {
  Score(json.string(instructions), list.map(levels, json.string))
}

pub type Request {
  Request(model: String, state: Json, questions: List(#(String, Question)))
}

pub fn request_to_json(request: Request) -> Json {
  let Request(model:, state:, questions:) = request
  json.object([
    #("state", state),
    #("model", json.string(model)),
    #("questions", json.object(list.map(questions, question_entry))),
  ])
}

fn question_entry(entry) {
  let #(key, question) = entry
  #(key, question_to_json(question))
}

pub fn question_to_json(question: Question) -> Json {
  case question {
    Noul(instructions:, criteria:) -> {
      let criteria = case criteria {
        Some(NoulCriteria(true: yes, false: no)) -> [
          #("criteria", json.object([#("true", yes), #("false", no)])),
        ]
        None -> []
      }
      json.object([
        #("type", json.string("noul")),
        #("instructions", instructions),
        ..criteria
      ])
    }
    Choice(instructions:, criteria:) ->
      json.object([
        #("type", json.string("choice")),
        #("instructions", instructions),
        #(
          "criteria",
          json.object(
            list.map(criteria, fn(option) {
              let #(key, description) = option
              #(key, json.nullable(description, fn(x) { x }))
            }),
          ),
        ),
      ])
    Score(instructions:, criteria:) ->
      json.object([
        #("type", json.string("score")),
        #("instructions", instructions),
        #("criteria", json.preprocessed_array(criteria)),
      ])
  }
}

/// Ask the questions about the state.
pub fn system_one(request: Request) -> Operation(BitArray) {
  let body = json.to_string(request_to_json(request))
  operation.post("/v1/systemone")
  |> operation.set_header("content-type", "application/json")
  |> operation.set_body(<<body:utf8>>)
}

pub type Evaluation {
  Evaluation(model: String, answers: Dict(String, Answer), usage: Usage)
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

pub type Answer {
  NoulAnswer(noul: Float)
  ChoiceAnswer(
    choice: String,
    probabilities: Dict(String, Float),
    confidence: Float,
  )
  ScoreAnswer(
    score: Float,
    legend: Dict(String, String),
    probabilities: Dict(String, Float),
    confidence: Float,
  )
}

pub fn system_one_response(
  response: Response(BitArray),
) -> Result(Evaluation, Failure) {
  case response.status {
    200 -> decode_body(response.body, evaluation_decoder())
    _ -> Error(failure(response))
  }
}

pub fn evaluation_decoder() -> decode.Decoder(Evaluation) {
  use model <- decode.field("model", decode.string)
  use answers <- decode.field(
    "answers",
    decode.dict(decode.string, answer_decoder()),
  )
  use usage <- decode.field("usage", usage_decoder())
  decode.success(Evaluation(model:, answers:, usage:))
}

fn usage_decoder() {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Usage(input_tokens:, output_tokens:))
}

fn answer_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "noul" -> {
      use noul <- decode.field("noul", number())
      decode.success(NoulAnswer(noul:))
    }
    "choice" -> {
      use choice <- decode.field("choice", decode.string)
      use probabilities <- decode.field("probabilities", probabilities())
      use confidence <- decode.field("confidence", number())
      decode.success(ChoiceAnswer(choice:, probabilities:, confidence:))
    }
    "score" -> {
      use score <- decode.field("score", number())
      use legend <- decode.field(
        "legend",
        decode.dict(decode.string, decode.string),
      )
      use probabilities <- decode.field("probabilities", probabilities())
      use confidence <- decode.field("confidence", number())
      decode.success(ScoreAnswer(score:, legend:, probabilities:, confidence:))
    }
    _ -> decode.failure(NoulAnswer(0.0), "Answer")
  }
}

fn probabilities() {
  decode.dict(decode.string, number())
}

// On Erlang a whole number such as `1` is not a float.
fn number() {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

/// The probability of each option in a choice answer, highest first.
pub fn ranked(probabilities: Dict(String, Float)) -> List(#(String, Float)) {
  dict.to_list(probabilities)
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
}

pub fn list_models() -> Operation(BitArray) {
  operation.get("/v1/models")
}

pub type Model {
  Model(name: String, description: String, release_date: String)
}

pub fn list_models_response(
  response: Response(BitArray),
) -> Result(List(Model), Failure) {
  case response.status {
    200 -> decode_body(response.body, models_decoder())
    _ -> Error(failure(response))
  }
}

fn models_decoder() {
  decode.field(
    "models",
    decode.list({
      use name <- decode.field("name", decode.string)
      use description <- decode.field("description", decode.string)
      use release_date <- decode.field("release_date", decode.string)
      decode.success(Model(name:, description:, release_date:))
    }),
    decode.success,
  )
}

/// Add the API key to an operation.
pub fn authorize(operation: Operation(t), api_key: String) -> Operation(t) {
  operation.set_header(operation, "authorization", "Bearer " <> api_key)
}

/// An authorized request to the TypeSafe API.
pub fn to_request(
  operation: Operation(t),
  api_key: String,
) -> request.Request(t) {
  operation
  |> authorize(api_key)
  |> operation.to_request(origin())
}

/// TypeSafe tags every response with an id to quote when reporting issues.
pub fn request_id(response: Response(a)) -> Result(String, Nil) {
  response.get_header(response, "x-typesafe-request-id")
}

pub type Failure {
  /// Status 401 when the key is invalid or 403 when it is missing.
  Unauthenticated(message: String)
  /// Status 400, for example an unknown model or more than 255 options.
  BadRequest(message: String)
  /// Status 422, the body failed validation.
  InvalidRequest(problems: List(Problem))
  /// Status 429, back off before retrying.
  RateLimited(retry_after: Option(Int))
  /// Status 529, back off before retrying.
  Overloaded(retry_after: Option(Int))
  UnexpectedResponse(status: Int, body: BitArray)
  UnableToDecode(reason: json.DecodeError)
}

/// A validation problem, `location` is the path to the offending field.
pub type Problem {
  Problem(location: List(String), message: String)
}

fn failure(response: Response(BitArray)) -> Failure {
  let Response(status:, body:, ..) = response
  let retry_after =
    response.get_header(response, "retry-after")
    |> result.try(int.parse)
    |> option.from_result
  case status {
    401 | 403 ->
      decode_message(body)
      |> result.map(Unauthenticated)
      |> result.unwrap(UnexpectedResponse(status:, body:))
    400 ->
      decode_message(body)
      |> result.map(BadRequest)
      |> result.unwrap(UnexpectedResponse(status:, body:))
    422 ->
      json.parse_bits(body, decode.at(["detail"], decode.list(problem())))
      |> result.map(InvalidRequest)
      |> result.unwrap(UnexpectedResponse(status:, body:))
    429 -> RateLimited(retry_after)
    529 -> Overloaded(retry_after)
    _ -> UnexpectedResponse(status:, body:)
  }
}

// The detail is either a message or an object with a message.
fn decode_message(body) {
  let decoder =
    decode.one_of(decode.at(["detail", "message"], decode.string), [
      decode.at(["detail"], decode.string),
    ])
  json.parse_bits(body, decoder)
  |> result.replace_error(Nil)
}

fn problem() {
  let segment =
    decode.one_of(decode.string, [decode.int |> decode.map(int.to_string)])
  use location <- decode.field("loc", decode.list(segment))
  use message <- decode.field("msg", decode.string)
  decode.success(Problem(location:, message:))
}

fn decode_body(body, decoder) {
  json.parse_bits(body, decoder)
  |> result.map_error(UnableToDecode)
}

/// Milliseconds to wait before retrying, `Error` if the failure is not temporary.
/// Uses the server's `retry-after` when given, otherwise exponential backoff.
pub fn retry_delay(failure: Failure, attempt: Int) -> Result(Int, Nil) {
  case failure {
    RateLimited(Some(seconds)) | Overloaded(Some(seconds)) -> Ok(seconds * 1000)
    RateLimited(None) | Overloaded(None) -> Ok(backoff(attempt))
    UnexpectedResponse(status:, ..) if status >= 500 -> Ok(backoff(attempt))
    _ -> Error(Nil)
  }
}

fn backoff(attempt) {
  int.min(500 * int.bitwise_shift_left(1, attempt), 8000)
}
