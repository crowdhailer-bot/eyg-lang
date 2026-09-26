import birdie
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import intelligence/jev
import midas/continuation.{type Continuation as K}
import midas/effect
import ogre/origin
import simplifile

pub type Effect(t) {
  Done(t)
  Fetch(
    request: request.Request(BitArray),
    resume: fn(Result(response.Response(BitArray), effect.FetchError)) ->
      Effect(t),
  )
}

fn fetch(
  request,
) -> K(Effect(t), Result(response.Response(BitArray), effect.FetchError)) {
  Fetch(request, _)
}

pub fn context() {
  jev.Client(
    origin: origin.https("typesafe.test"),
    token: "tok_123",
    model: "jev-test",
    fetch: fetch,
  )
}

fn fixture(name) {
  let assert Ok(body) =
    simplifile.read_bits("test/fixtures/" <> name <> ".json")
  body
}

fn reply(status, name) {
  response.new(status) |> response.set_body(fixture(name))
}

fn evaluate(response) {
  let assert Fetch(resume:, ..) =
    jev.evaluate(context(), "Hello", {
      use answer <- jev.and(jev.noul("Is this urgent?", None, None))
      jev.return(answer)
    })(Done)
  let assert Done(result) = resume(Ok(response))
  result
}

// Object order is insignificant in JSON, but JavaScript reorders integer keys.
// Sort keys and indent objects so snapshots are readable and target-independent.
fn json_snapshot(body) {
  let assert Ok(text) = json.parse(body, json_text_decoder())
  text
}

fn json_text_decoder() {
  decode.recursive(fn() {
    decode.one_of(
      decode.map(decode.dict(decode.string, json_text_decoder()), fn(fields) {
        let fields =
          fields
          |> dict.to_list
          |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
          |> list.map(fn(field) {
            json.to_string(json.string(field.0)) <> ": " <> field.1
          })
          |> string.join(",\n")
          |> string.replace("\n", "\n  ")
        "{\n  " <> fields <> "\n}"
      }),
      [
        decode.map(decode.list(json_text_decoder()), fn(items) {
          "[" <> string.join(items, ", ") <> "]"
        }),
        decode.map(decode.string, fn(value) {
          json.to_string(json.string(value))
        }),
        decode.map(decode.int, fn(value) { json.to_string(json.int(value)) }),
        decode.map(decode.float, fn(value) { json.to_string(json.float(value)) }),
        decode.map(decode.bool, fn(value) { json.to_string(json.bool(value)) }),
        decode.map(decode.optional(decode.string), fn(_) { "null" }),
      ],
    )
  })
}

pub type Team {
  Billing
  Technical
  Sales
}

pub fn encode_all_question_types_test() {
  let assert Fetch(request:, resume:) =
    jev.evaluate(context(), "Hello", {
      use noul <- jev.and(jev.noul("Is this urgent?", None, None))
      use choice <- jev.and(jev.choice(
        "Which team?",
        [
          jev.option("billing", Billing, "Payments, invoicing, refunds"),
          jev.option("technical", Technical, "Bugs, outages, integrations"),
          jev.option("sales", Sales, "Pricing, upgrades, new accounts"),
        ],
        Billing,
      ))
      use score <- jev.and(
        jev.score("How frustrated?", ["Calm", "Frustrated", "Very angry"]),
      )
      jev.return(#(noul, choice, score))
    })(Done)
  let assert Ok(body) = bit_array.to_string(request.body)
  birdie.snap(json_snapshot(body), "encode_all_question_types_test")
  assert request.method == http.Post
  assert request.scheme == http.Https
  assert request.host == "typesafe.test"
  assert request.path == "/v1/systemone"
  assert request.get_header(request, "content-type") == Ok("application/json")
  let assert Done(result) = resume(Ok(reply(200, "evaluation")))
  let assert Ok(evaluation) = result
  assert "jev-1.13.0" == evaluation.model
  assert jev.Usage(input_tokens: 390, output_tokens: 73) == evaluation.usage
  let #(noul, choice, score) = evaluation.answer
  assert 0.95 == noul
  assert #(
      Billing,
      dict.from_list([#(Billing, 0.87), #(Technical, 0.13), #(Sales, 0.0)]),
      0.81,
    )
    == choice

  assert #(
      1.03,
      dict.from_list([
        #("0", "Calm"),
        #("1", "Frustrated"),
        #("2", "Very angry"),
      ]),
      dict.from_list([#("0", 0.0), #("1", 0.97), #("2", 0.03)]),
      0.95,
    )
    == score
}

pub fn whole_number_answers_decode_test() {
  let assert Fetch(resume:, ..) =
    jev.evaluate(context(), "Hello", {
      use noul <- jev.and(jev.noul("Is this urgent?", None, None))
      use choice <- jev.and(jev.choice(
        "Which team?",
        [jev.option("billing", Billing, "Payments")],
        Billing,
      ))
      use score <- jev.and(jev.score("How frustrated?", ["Calm", "Angry"]))
      jev.return(#(noul, choice, score))
    })(Done)
  let assert Done(Ok(evaluation)) = resume(Ok(reply(200, "whole_numbers")))
  assert evaluation.answer
    == #(
      1.0,
      #(Billing, dict.from_list([#(Billing, 1.0)]), 1.0),
      #(
        0.0,
        dict.from_list([#("0", "Calm"), #("1", "Angry")]),
        dict.from_list([#("0", 1.0), #("1", 0.0)]),
        1.0,
      ),
    )
}

pub fn invalid_key_is_unauthenticated_test() {
  let assert Error(jev.Unauthenticated(message)) =
    evaluate(reply(401, "unauthorized"))
  birdie.snap(message, "invalid API key")
}

// Recorded responses return 403 when the key is missing.
pub fn missing_key_is_unauthenticated_test() {
  let assert Error(jev.Unauthenticated(message)) =
    evaluate(reply(403, "missing_auth"))
  birdie.snap(message, "missing API key")
}

pub fn unknown_model_is_a_bad_request_test() {
  assert evaluate(reply(400, "unknown_model"))
    == Error(jev.BadRequest("Unknown model: jev-9"))
}

pub fn too_many_options_is_a_bad_request_test() {
  let assert Error(jev.BadRequest(message)) = evaluate(reply(400, "choice_256"))
  birdie.snap(message, "too many choice options")
}

pub fn too_many_tokens_test() {
  assert evaluate(reply(400, "max_tokens")) == Error(jev.TooManyTokens)
}

pub fn missing_field_reports_the_location_test() {
  assert evaluate(reply(422, "missing_state"))
    == Error(
      jev.InvalidRequest([jev.Problem(["body", "state"], "Field required")]),
    )
}

pub fn empty_questions_reports_the_location_test() {
  let assert Error(jev.InvalidRequest([problem])) =
    evaluate(reply(422, "empty_questions"))
  assert problem.location == ["body", "questions"]
  birdie.snap(problem.message, "empty questions validation")
}

pub fn missing_answers_are_a_decode_failure_test() {
  let body =
    json.object([
      #("model", json.string("jev-test")),
      #(
        "usage",
        json.object([
          #("input_tokens", json.int(1)),
          #("output_tokens", json.int(1)),
        ]),
      ),
    ])
    |> json.to_string
  let assert Error(jev.UnableToDecode(_)) =
    response.new(200) |> response.set_body(<<body:utf8>>) |> evaluate
}
