import eyg/cli/helpers
import eyg/cli/tui/agent
import eyg/cli/tui/model
import eyg/cli/tui/shell
import gleam/int
import gleam/javascript/promise
import gleam/json as j
import gleam/list
import gleam/option.{Some}
import gleam/string
import javascript/mutable_reference as ref
import loam/source
import loam/system
import plinthx/browser/fetch
import plinthx/bun/runtime as bun
import plinthx/bun/server

/// A model that asks to run the code once, then replies with text.
fn fixture(code) {
  let requests = ref.new(0)
  let assert Ok(host) = bun.get()
  let assert Ok(server) =
    server.serve(
      host,
      server.Options(0, "127.0.0.1", fn(_request) {
        let _ = ref.update(requests, fn(count) { count + 1 })
        let count = ref.get(requests)
        let message = case count {
          1 ->
            j.object([
              #("content", j.string("I will run that now.")),
              #(
                "tool_calls",
                j.preprocessed_array([
                  j.object([
                    #(
                      "function",
                      j.object([
                        #("name", j.string("run")),
                        #("arguments", j.object([#("code", j.string(code))])),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ])
          _ -> j.object([#("content", j.string("The clock returned."))])
        }
        let body =
          j.object([#("message", message), #("done", j.bool(True))])
          |> j.to_string
        let assert Ok(constructor) = fetch.get_response()
        let assert Ok(response) =
          fetch.new_response(constructor, body <> "\n", 200, [
            #("content-type", "application/x-ndjson"),
          ])
        promise.resolve(response)
      }),
    )
  server
}

const policy_fields = [
  "acquire", "mount", "append_file", "create_key", "cwd", "delete_file", "env",
  "exit", "fetch", "flip", "make_directory", "now", "random", "read_directory",
  "read_file", "sleep", "standard_error", "standard_in", "standard_out",
  "write_file",
]

/// Every gate passes, except those overridden.
fn policy(overrides) {
  let fields =
    list.map(policy_fields, fn(field) {
      let gate = case list.key_find(overrides, field) {
        Ok(gate) -> gate
        Error(Nil) -> "(x) -> { Pass(x) }"
      }
      field <> ": " <> gate
    })
  "{ " <> string.join(fields, ", ") <> " }"
}

fn config(server, policy) {
  let origin = "http://127.0.0.1:" <> int.to_string(server.port(server))
  "{ llm: { provider: Ollama({origin: \""
  <> origin
  <> "\", api_key: None({})}), model: \"fixture\" }, policy: "
  <> policy
  <> ", context: {} }"
}

fn advanced(effect) {
  use #(events, progress) <- promise.await(shell.advance(effect, 1000.0))
  case progress {
    shell.Paused(effect) -> {
      use #(more, progress) <- promise.map(advanced(effect))
      #(list.append(events, more), progress)
    }
    _ -> promise.resolve(#(events, progress))
  }
}

fn finished(effect) {
  use #(events, progress) <- promise.map(advanced(effect))
  let assert shell.Finished(value) = progress
  #(events, value)
}

/// Perform the commands of a turn as the tui loop does, until it is saved.
fn drive(model: model.Model, commands) {
  let assert Some(running) = model.agent
  case commands {
    [] -> promise.resolve(model)
    [model.Ask(id, text), ..rest] -> {
      use #(events, #(result, running)) <- promise.await(
        finished(agent.ask(running, text)),
      )
      let model =
        list.fold(events, model, fn(model, event) {
          model.received(model, id, event)
        })
      let #(model, more) = model.generated(model, id, result, running)
      drive(model, list.append(rest, more))
    }
    [model.Generate(id), ..rest] -> {
      use #(events, #(result, running)) <- promise.await(
        finished(agent.generate(running)),
      )
      let model =
        list.fold(events, model, fn(model, event) {
          model.received(model, id, event)
        })
      let #(model, more) = model.generated(model, id, result, running)
      drive(model, list.append(rest, more))
    }
    [model.Call(id, call, index), ..rest] -> {
      use #(_, #(result, performed, running)) <- promise.await(
        finished(agent.call(running, call, index)),
      )
      let #(model, more) =
        model.called(model, id, result, performed, running, 1.0)
      drive(model, list.append(rest, more))
    }
    [model.Save(_), ..rest] -> {
      use #(_, saved) <- promise.await(finished(agent.save(running)))
      drive(model.saved(model, saved), rest)
    }
    [_, ..rest] -> drive(model, rest)
  }
}

pub fn a_turn_streams_text_runs_tools_and_logs_decisions_test() {
  let code = "let _ = perform StandardOut(\"hello\") perform Now({})"
  let server = fixture(code)
  let policy =
    policy([
      #("standard_out", "(x) -> { Pass(!string_uppercase(x)) }"),
      #("now", "(_) -> { Mock(123) }"),
    ])
  let start = agent.start(source.Code(config(server, policy)), helpers.config)
  use started <- promise.await(system.run(start))
  let assert Ok(running) = started
  assert agent.model_name(running) == "fixture"
  let model = model.agent_started(model.new(".", True), running)
  let model =
    "Say hello and read the clock."
    |> string.to_graphemes
    |> list.fold(model, fn(model, key) { model.key(model, key).0 })
  let #(model, commands) = model.key(model, "enter")
  use model <- promise.await(drive(model, commands))
  use _ <- promise.map(server.stop(server, True))
  let roles = list.map(model.entries, fn(entry) { entry.role })
  assert roles == [model.User, model.Assistant, model.Tool, model.Assistant]
  let assert [user, first, tool, last] = model.entries
  assert string.starts_with(user.output, "trace saved to ")
  assert first.output == "I will run that now."
  assert tool.source == code
  assert tool.performed
    == [
      shell.Performed("StandardOut", "\"hello\"", "{}", Some("altered")),
      shell.Performed("Now", "{}", "123", Some("mocked")),
    ]
  assert last.output == "The clock returned."
  assert !model.busy
}
