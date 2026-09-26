import eyg/interpreter/value as v
import gleam/fetch
import gleam/http/response
import gleam/javascript/promise
import gleam/json
import gleam/option.{None}
import gleam/string
import javascript/mutable_reference
import overlay/eval/agent.{Reply}
import overlay/eval/cassette
import overlay/eval/environment
import overlay/eval/model
import overlay/eval/session
import overlay/eval/transcript

fn scripted_transport() {
  let remaining =
    mutable_reference.new([
      agent.stream(Reply("", ["!int_add(3, 4)"])),
      agent.stream(Reply("Seven", [])),
    ])
  fn(_request) {
    let chunks = case mutable_reference.get(remaining) {
      [chunks, ..rest] -> {
        let _ = mutable_reference.set(remaining, rest)
        chunks
      }
      [] -> []
    }
    promise.resolve(Ok(response.Response(200, [], session.reader(chunks))))
  }
}

fn config(transport, prompt) {
  let assert model.Provider(llm:, ..) = model.ollama_cloud("m", "k")
  session.Config(
    environment: environment.empty(),
    context: session.NoContext,
    model: model.Provider(llm:, transport:),
    workspace: None,
    prompts: [prompt],
    max_model_calls: 5,
  )
}

pub fn a_recorded_session_replays_test() {
  let recorder = cassette.recorder()
  let transport = cassette.record(scripted_transport(), recorder)
  use recorded <- promise.await(session.run(config(transport, "add")))
  let cassette = cassette.recorded(recorder)
  let assert [_, _] = cassette.interactions

  // Cassettes are stored as JSON.
  let assert Ok(cassette) =
    cassette.encode(cassette)
    |> json.to_string
    |> json.parse(cassette.decoder())

  let transport = cassette.replay(cassette, cassette.Strict)
  use replayed <- promise.map(session.run(config(transport, "add")))
  assert recorded == replayed
  let assert [run] = transcript.runs(replayed)
  assert transcript.Computed(v.Integer(7)) == run.outcome
}

pub fn a_changed_session_does_not_replay_strictly_test() {
  let recorder = cassette.recorder()
  let transport = cassette.record(scripted_transport(), recorder)
  use _ <- promise.await(session.run(config(transport, "add")))
  let cassette = cassette.recorded(recorder)

  let strict = cassette.replay(cassette, cassette.Strict)
  use changed <- promise.await(session.run(config(strict, "add again")))
  let assert transcript.ModelFailed(reason) = changed.stop
  assert string.contains(reason, "differs from the recording")

  let lenient = cassette.replay(cassette, cassette.Lenient)
  use changed <- promise.map(session.run(config(lenient, "add again")))
  assert transcript.Finished == changed.stop
}

pub fn binary_bodies_are_kept_test() {
  let cassette = cassette.Cassette([cassette.Interaction("k", 200, <<255, 0>>)])
  let assert Ok(decoded) =
    cassette.encode(cassette)
    |> json.to_string
    |> json.parse(cassette.decoder())
  assert cassette == decoded
}

pub fn a_failed_stream_cannot_replay_as_a_success_test() {
  let recorder = cassette.recorder()
  let failed = fn(_) {
    promise.resolve(
      Ok(
        response.Response(200, [], fn() {
          promise.resolve(Error(fetch.NetworkError("stream disconnected")))
        }),
      ),
    )
  }
  use original <- promise.await(
    session.run(config(cassette.record(failed, recorder), "add")),
  )
  let assert transcript.ModelFailed(_) = original.stop
  let recorded = cassette.recorded(recorder)
  assert [] == recorded.interactions
  use replayed <- promise.map(
    session.run(config(cassette.replay(recorded, cassette.Strict), "add")),
  )
  let assert transcript.ModelFailed(_) = replayed.stop
}
