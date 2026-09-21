# jev

Client for [TypeSafe](https://docs.typesafe.ai/llms.txt)'s System One API and its Jev decision model.
Jev is not a text generator: it answers typed questions about a state with probabilities.

The client builds `Operation`s and decodes `Response`s without doing IO,
send them with the HTTP client of your runtime.

```gleam
import gleam/json
import jev

let request =
  jev.Request(model: jev.latest, state: json.string("Help! My payouts are failing."), questions: [
    #("urgent", jev.noul("Does this convey urgency?")),
    #("team", jev.choice("Which team should handle this?", [
      #("billing", "Payments, invoicing, refunds"),
      #("technical", "Bugs, outages, integrations"),
    ])),
  ])

let http_request = jev.system_one(request) |> jev.to_request(api_key)
// send http_request, then
let assert Ok(jev.Evaluation(answers:, usage:, ..)) = jev.system_one_response(http_response)
```

## Endpoints

| Function | Endpoint | Decoder |
| --- | --- | --- |
| `system_one(Request)` | `POST /v1/systemone` | `system_one_response` returns an `Evaluation` |
| `list_models()` | `GET /v1/models` | `list_models_response` returns a list of `Model` |

`authorize` adds the bearer token to an operation, for example when a proxy holds the key.
`to_request` authorizes and targets `https://api.typesafe.ai`.

## Questions and answers

| Question | Criteria | Answer |
| --- | --- | --- |
| `Noul` yes/no | optional description of yes and no | `NoulAnswer(noul)` probability of yes |
| `Choice` pick one option | option name to description, at most 255 | `ChoiceAnswer(choice, probabilities, confidence)` |
| `Score` rate on levels | ordered level descriptions, at most 10 | `ScoreAnswer(score, legend, probabilities, confidence)` |

Instructions and criteria are `Json` so they can be strings, objects or arrays.
`noul`, `choice` and `score` build questions from plain strings.
`ranked` orders choice probabilities from most to least likely.

Every question is evaluated independently against the same state, so asking many questions in one request costs little extra time.
Input tokens are charged, output tokens are free. A choice option costs about ten tokens.

## Failures

| Status | Failure | Body |
| --- | --- | --- |
| 401 invalid key, 403 missing key | `Unauthenticated(message)` | `{"detail": {"error_type", "message"}}` |
| 400 | `BadRequest(message)` | `{"detail": {"error_type", "message"}}` or `{"detail": message}` |
| 422 | `InvalidRequest(problems)` | `{"detail": [{"loc", "msg", ..}]}` |
| 429 | `RateLimited(retry_after)` | |
| 529 | `Overloaded(retry_after)` | |
| other | `UnexpectedResponse(status, body)` | |

`retry_delay(failure, attempt)` gives the milliseconds to wait before retrying a temporary failure,
honouring `retry-after` and otherwise backing off exponentially from 500ms up to 8s.
`request_id` reads the `x-typesafe-request-id` header to quote when reporting issues.

## Observed behaviour

Recorded against `jev-1.13.0` on 2026-09-21, the fixtures in `test/fixtures` are real responses.

- A missing key returns 403, not the documented 401.
- An unknown model, an unknown question type, more than 255 options, an empty choice or more than 10 levels return 400, which the docs do not list.
  An unknown question type only says `Invalid request.`.
- A score with a single level is accepted although the docs ask for at least two.
- Browsers are refused: CORS rejects `localhost` origins, so browser apps need a proxy.
- Typical latency is 80ms upstream and 0.7s for the round trip; a 255 option choice uses about 2,700 input tokens.

## Development

```sh
gleam test
gleam test --target javascript --runtime bun
```
