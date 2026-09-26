# intelligence

A type-safe implementation of evaluating questions using the Jev mode from typesafe.ai.

[![Package Version](https://img.shields.io/hexpm/v/intelligence)](https://hex.pm/packages/intelligence)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/intelligence/)

```sh
gleam add intelligence@1 midas@3
```

This package builds on [Midas](https://hexdocs.pm/midas/) continuations so logic can be run on the JavaScript or BEAM runtimes.

## Example

```gleam
import intelligence/jev
import midas/continuation.{type Continuation as K}

pub type Team {
  Billing
  Technical
  Sales
}

pub type Triage {
  Triage(
    urgency: Float,
    team: Team,
    frustration: Float,
  )
}

fn questions() -> jev.Bundle(Triage) {
  use urgency <- jev.and(jev.noul("Does this message need urgent attention?"))
  use team <- jev.and(jev.choice(
    "Which team should handle this message?",
    [
      jev.option("billing", Billing, "Payments, invoicing, refunds"),
      jev.option("technical", Technical, "Bugs, outages, integrations"),
      jev.option("sales", Sales, "Pricing, upgrades, new accounts"),
    ],
    Billing,
  ))
  use frustration <- jev.and(jev.score("How frustrated is the customer?", [
    "Calm", "Frustrated", "Very angry",
  ]))
  let #(team, _probabilities, _confidence) = team
  let #(frustration, _legend, _probabilities, _confidence) = frustration
  jev.return(Triage(urgency, team, frustration))
}

pub fn classify(
  client: jev.Client(t),
  message: String,
) -> K(t, Result(jev.Evaluation(Triage), jev.Failure)) {
  jev.evaluate(client, message, questions())
}
```

## Run with httpc

```sh
gleam add gleam_httpc
```

This adapter runs the continuation and returns the result directly. Put it in
a separate module, importing the `triage` module above:

```gleam
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/result
import intelligence/jev
import midas/continuation.{type Continuation as K}
import midas/effect
import ogre/origin
import triage

pub type Outcome =
  Result(jev.Evaluation(triage.Triage), jev.Failure)

fn send(
  request: Request(BitArray),
) -> K(t, Result(Response(BitArray), effect.FetchError)) {
  httpc.send_bits(request)
  |> result.map_error(fn(error) {
    case error {
      httpc.InvalidUtf8Response -> effect.UnableToReadBody
      httpc.FailedToConnect(..) -> effect.NetworkError("Failed to connect")
      httpc.ResponseTimeout -> effect.NetworkError("Response timed out")
    }
  })
  |> continuation.return
}

pub fn client(api_key: String) -> jev.Client(Outcome) {
  jev.Client(
    origin: origin.https("api.typesafe.ai"),
    token: api_key,
    model: "jev-latest",
    fetch: send,
  )
}

pub fn run_classify(
  client: jev.Client(Outcome),
  message: String,
) -> Outcome {
  triage.classify(client, message)(fn(result) { result })
}
```


## Development

```sh
gleam test
gleam format
```
