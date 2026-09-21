import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleeunit
import jev
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

fn fixture(name) {
  let assert Ok(body) =
    simplifile.read_bits("test/fixtures/" <> name <> ".json")
  body
}

fn reply(status, name) {
  response.new(status) |> response.set_body(fixture(name))
}

pub fn request_encodes_every_question_type_test() {
  let request =
    jev.Request(model: jev.latest, state: json.string("Help!"), questions: [
      #("urgent", jev.noul("Is this urgent?")),
      #("team", jev.choice("Which team?", [#("billing", "Payments")])),
      #("mood", jev.score("How frustrated?", ["Calm", "Angry"])),
    ])
  assert json.to_string(jev.request_to_json(request))
    == "{\"state\":\"Help!\",\"model\":\"jev-latest\",\"questions\":{"
    <> "\"urgent\":{\"type\":\"noul\",\"instructions\":\"Is this urgent?\"},"
    <> "\"team\":{\"type\":\"choice\",\"instructions\":\"Which team?\",\"criteria\":{\"billing\":\"Payments\"}},"
    <> "\"mood\":{\"type\":\"score\",\"instructions\":\"How frustrated?\",\"criteria\":[\"Calm\",\"Angry\"]}}}"
}

pub fn choice_options_without_description_are_null_test() {
  let question = jev.Choice(json.string("Which?"), [#("a", None)])
  assert json.to_string(jev.question_to_json(question))
    == "{\"type\":\"choice\",\"instructions\":\"Which?\",\"criteria\":{\"a\":null}}"
}

pub fn noul_criteria_are_encoded_test() {
  let criteria = jev.NoulCriteria(json.string("urgent"), json.string("calm"))
  let question = jev.Noul(json.string("Is it urgent?"), Some(criteria))
  assert json.to_string(jev.question_to_json(question))
    == "{\"type\":\"noul\",\"instructions\":\"Is it urgent?\",\"criteria\":{\"true\":\"urgent\",\"false\":\"calm\"}}"
}

pub fn authorized_request_targets_the_system_one_endpoint_test() {
  let request =
    jev.Request(model: jev.latest, state: json.null(), questions: [])
    |> jev.system_one
    |> jev.to_request("secret")
  assert request.method == http.Post
  assert request.host == "api.typesafe.ai"
  assert request.path == "/v1/systemone"
  assert request.get_header(request, "authorization") == Ok("Bearer secret")
  assert request.get_header(request, "content-type") == Ok("application/json")
}

pub fn evaluation_decodes_every_answer_type_test() {
  let assert Ok(evaluation) = jev.system_one_response(reply(200, "evaluation"))
  let jev.Evaluation(model:, answers:, usage:) = evaluation
  assert model == "jev-1.13.0"
  assert usage == jev.Usage(input_tokens: 390, output_tokens: 73)
  assert dict.get(answers, "is_urgent") == Ok(jev.NoulAnswer(0.95))
  let assert Ok(jev.ChoiceAnswer(choice:, probabilities:, confidence:)) =
    dict.get(answers, "department")
  assert choice == "billing"
  assert confidence == 0.81
  assert jev.ranked(probabilities)
    == [#("billing", 0.87), #("technical", 0.13), #("sales", 0.0)]
  let assert Ok(jev.ScoreAnswer(score:, legend:, ..)) =
    dict.get(answers, "frustration")
  assert score == 1.03
  assert dict.get(legend, "2") == Ok("Very angry")
}

pub fn whole_number_probabilities_decode_test() {
  let body = <<
    "{\"model\":\"m\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"a\",\"confidence\":1,\"probabilities\":{\"a\":1}}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}":utf8,
  >>
  let assert Ok(evaluation) =
    jev.system_one_response(response.new(200) |> response.set_body(body))
  assert dict.get(evaluation.answers, "q")
    == Ok(jev.ChoiceAnswer("a", dict.from_list([#("a", 1.0)]), 1.0))
}

pub fn invalid_key_is_unauthenticated_test() {
  let assert Error(jev.Unauthenticated(message)) =
    jev.system_one_response(reply(401, "unauthorized"))
  assert message
    == "Cannot authenticate with the server. Please check your API key and try again."
}

// The documentation says 401 but a missing key gets a 403.
pub fn missing_key_is_unauthenticated_test() {
  let assert Error(jev.Unauthenticated(message)) =
    jev.system_one_response(reply(403, "missing_auth"))
  assert message == "Must supply an API key! Check your request and try again."
}

pub fn unknown_model_is_a_bad_request_test() {
  assert jev.system_one_response(reply(400, "unknown_model"))
    == Error(jev.BadRequest("Unknown model: jev-9"))
}

pub fn too_many_options_is_a_bad_request_test() {
  assert jev.system_one_response(reply(400, "choice_256"))
    == Error(jev.BadRequest("Too many choices. Must have at most 255 choices."))
}

pub fn missing_field_reports_the_location_test() {
  assert jev.system_one_response(reply(422, "missing_state"))
    == Error(
      jev.InvalidRequest([jev.Problem(["body", "state"], "Field required")]),
    )
}

pub fn empty_questions_reports_the_location_test() {
  let assert Error(jev.InvalidRequest([problem])) =
    jev.system_one_response(reply(422, "empty_questions"))
  assert problem.location == ["body", "questions"]
}

pub fn malformed_json_reports_the_offset_test() {
  assert jev.system_one_response(reply(422, "invalid_json"))
    == Error(
      jev.InvalidRequest([jev.Problem(["body", "9"], "JSON decode error")]),
    )
}

pub fn rate_limit_reads_retry_after_test() {
  let failure =
    response.new(429)
    |> response.set_header("retry-after", "3")
    |> response.set_body(<<>>)
    |> jev.system_one_response
  assert failure == Error(jev.RateLimited(Some(3)))
}

pub fn unknown_path_is_unexpected_test() {
  let assert Error(jev.UnexpectedResponse(status: 404, ..)) =
    jev.system_one_response(reply(404, "not_found"))
}

pub fn temporary_failures_are_retried_with_backoff_test() {
  assert jev.retry_delay(jev.RateLimited(Some(2)), 0) == Ok(2000)
  assert jev.retry_delay(jev.Overloaded(None), 0) == Ok(500)
  assert jev.retry_delay(jev.Overloaded(None), 2) == Ok(2000)
  assert jev.retry_delay(jev.Overloaded(None), 10) == Ok(8000)
  assert jev.retry_delay(jev.UnexpectedResponse(502, <<>>), 1) == Ok(1000)
}

pub fn permanent_failures_are_not_retried_test() {
  assert jev.retry_delay(jev.BadRequest("no"), 0) == Error(Nil)
  assert jev.retry_delay(jev.Unauthenticated("no"), 0) == Error(Nil)
}

pub fn models_decode_test() {
  let assert Ok([latest, preview]) =
    jev.list_models_response(reply(200, "models"))
  assert latest.name == "jev-latest"
  assert preview.name == "jev-preview"
}

pub fn request_id_is_read_from_the_header_test() {
  let response =
    response.new(200)
    |> response.set_header("x-typesafe-request-id", "req_1")
  assert jev.request_id(response) == Ok("req_1")
}
