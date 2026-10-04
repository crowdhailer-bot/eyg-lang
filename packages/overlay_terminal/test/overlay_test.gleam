import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/json as j
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import plinth/browser/request
import plinth/browser/response
import plinthx/bun
import plinthx/bun/server
import terminal/cell
import terminal/overlay
import terminal/process
import terminal/protocol as p

fn fixture(code) {
  let requests = cell.new([])
  let host = bun.get() |> should.be_ok
  let server =
    server.serve(
      host,
      server.Options("127.0.0.1", 0, fn(req, _) {
        use body <- promise.map(request.text(req))
        cell.write(requests, [should.be_ok(body), ..cell.read(requests)])
        let message = case list.length(cell.read(requests)) {
          1 ->
            j.object([
              #("content", j.string("I will run that now.")),
              #(
                "tool_calls",
                j.array(
                  [
                    j.object([
                      #(
                        "function",
                        j.object([
                          #("name", j.string("run")),
                          #("arguments", j.object([#("code", j.string(code))])),
                        ]),
                      ),
                    ]),
                  ],
                  fn(value) { value },
                ),
              ),
            ])
          _ -> j.object([#("content", j.string("The clock returned."))])
        }
        let body =
          j.object([#("message", message), #("done", j.bool(True))])
          |> j.to_string
        response.new(
          body <> "\n",
          response.Options(200, [#("content-type", "application/x-ndjson")]),
        )
        |> should.be_ok
      }),
    )
    |> should.be_ok
  #(server, requests)
}

fn arguments(server, policy) {
  let origin = "http://127.0.0.1:" <> int.to_string(server.port(server))
  [
    "overlay",
    "-c",
    "{ llm: { provider: Ollama({origin: \""
      <> origin
      <> "\", api_key: None({})}), model: \"fixture\" }, policy: "
      <> policy
      <> ", context: {} }",
  ]
}

pub fn streaming_policy_and_tool_history_test() {
  let code = "let _ = perform StandardOut(\"hello\") perform Now({})"
  let #(server, requests) = fixture(code)
  let events = cell.new([])
  use initialized <- promise.await(
    overlay.initialize(
      arguments(
        server,
        "{ standard_out: (x) -> { Pass(!string_uppercase(x)) }, now: (_) -> { Mock(123) } }",
      ),
      fn(event) { cell.write(events, [event, ..cell.read(events)]) },
      fn(_) { promise.resolve("") },
    ),
  )
  let runtime = should.be_ok(initialized)
  use Nil <- promise.await(overlay.evaluate(
    runtime,
    1,
    "Say hello and read the clock.",
  ))
  use _ <- promise.map(server.stop(server, True))
  let events = list.reverse(cell.read(events))
  list.contains(events, p.OverlayReady("fixture")) |> should.be_true
  list.any(events, fn(event) {
    case event {
      p.Tool(_, "run", found) -> found == code
      _ -> False
    }
  })
  |> should.be_true
  list.filter_map(events, fn(event) {
    case event {
      p.Effect(_, effect) -> Ok(effect)
      _ -> Error(Nil)
    }
  })
  |> should.equal([
    p.EffectRecord("StandardOut", "\"HELLO\"", "{}", Some("pass")),
    p.EffectRecord("Now", "{}", "123", Some("mock")),
  ])
  list.filter_map(events, fn(event) {
    case event {
      p.Assistant(_, text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
  |> string.concat
  |> string.contains("The clock returned.")
  |> should.be_true
  list.length(cell.read(requests)) |> should.equal(2)
  let decoder = {
    use messages <- decode.field(
      "messages",
      decode.list({
        use role <- decode.field("role", decode.string)
        use content <- decode.optional_field("content", "", decode.string)
        decode.success(#(role, content))
      }),
    )
    decode.success(messages)
  }
  cell.read(requests)
  |> list.first
  |> should.be_ok
  |> j.parse(decoder)
  |> should.be_ok
  |> list.any(fn(message) {
    message.0 == "tool" && string.contains(message.1, "123")
  })
  |> should.be_true
}

pub fn policy_prompt_crosses_process_boundary_and_denial_is_logged_test() {
  let #(server, _) = fixture("perform Now({})")
  let events = cell.new([])
  let runtime_ref = cell.new(None)
  let #(ready, mark_ready) = promise.start()
  let #(done, mark_done) = promise.start()
  let runtime =
    process.start(
      fn(event) {
        cell.write(events, [event, ..cell.read(events)])
        case event {
          p.OverlayReady(_) -> mark_ready(Nil)
          p.Complete(..) -> mark_done(Nil)
          p.Prompt(_, _) -> {
            let assert Some(runtime) = cell.read(runtime_ref)
            process.send(runtime, p.Reply("n")) |> should.be_ok
          }
          _ -> Nil
        }
      },
      [],
    )
    |> should.be_ok
  cell.write(runtime_ref, Some(runtime))
  process.send(
    runtime,
    p.Initialize(arguments(
      server,
      "{now: (_) -> { Ask({question: \"Read the clock?\", denied: 0}) }}",
    )),
  )
  |> should.be_ok
  use initialized <- promise.await(within(ready))
  should.be_ok(initialized)
  process.send(runtime, p.Evaluate(1, "What time is it?", False))
  |> should.be_ok
  use completed <- promise.await(within(done))
  use _ <- promise.await(process.terminate(runtime))
  use _ <- promise.map(server.stop(server, True))
  should.be_ok(completed)
  list.any(cell.read(events), fn(event) {
    case event {
      p.Prompt(_, text) -> string.contains(text, "Read the clock?")
      _ -> False
    }
  })
  |> should.be_true
  list.filter_map(cell.read(events), fn(event) {
    case event {
      p.Effect(_, effect) -> Ok(effect)
      _ -> Error(Nil)
    }
  })
  |> should.equal([p.EffectRecord("Now", "{}", "0", Some("mock"))])
}

fn within(work) {
  promise.race_list([
    promise.map(work, Ok),
    promise.wait(5000) |> promise.map(fn(_) { Error("Timed out") }),
  ])
}
