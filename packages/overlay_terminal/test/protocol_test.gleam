import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import terminal/protocol as p

pub fn all_event_shapes_roundtrip_test() {
  let view =
    p.View(
      [[p.Chunk("緑", "string", True, False, Some([2, 1]))]],
      "\"緑\"",
      "String",
      [],
      Some("ready"),
      Some(p.Input("value", "緑", [#("緑", "green")], "text")),
    )
  list.each(
    [
      p.Structural(view),
      p.Structural(p.View(..view, message: None, input: None)),
      p.Clipboard("hello"),
      p.Ready(["standard"]),
      p.OverlayReady("model"),
      p.Assistant(-1, "chunk"),
      p.Tool(-2, "run", "42"),
      p.ToolResult(-2, "42", False, 1.5),
      p.Packages([]),
      p.Output(1, "out", False),
      p.Effect(1, p.EffectRecord("Now", "{}", "123", Some("mock"))),
      p.Effect(1, p.EffectRecord("Now", "{}", "123", None)),
      p.Fetch(1, "https://example.com/modules"),
      p.Prompt(1, "Allow?"),
      p.Complete(1, [Ok("42"), Error("error")], "", 2.0),
      p.Failure(1, "bad"),
    ],
    fn(event) {
      p.encode_event(event)
      |> json.to_string
      |> json.parse(p.event_decoder())
      |> should.equal(Ok(event))
    },
  )
}

pub fn all_request_shapes_roundtrip_test() {
  list.each(
    [
      p.Initialize(["shell"]),
      p.Evaluate(1, "42", False),
      p.Evaluate(2, "", True),
      p.Reply("n"),
      p.Structure(p.Enter(None)),
      p.Structure(p.Enter(Some("42"))),
      p.Structure(p.Key("right")),
      p.Structure(p.Answer("42")),
      p.Structure(p.Paste("{}")),
      p.Structure(p.Focus([])),
      p.Structure(p.Cancel),
    ],
    fn(request) {
      p.encode_request(request)
      |> json.to_string
      |> json.parse(p.request_decoder())
      |> should.equal(Ok(request))
    },
  )
}

pub fn malformed_requests_fail_at_boundary_test() {
  json.parse("{\"type\":\"evaluate\",\"id\":\"wrong\"}", p.request_decoder())
  |> should.be_error
  json.parse("{\"type\":\"surprise\"}", p.request_decoder()) |> should.be_error
}
