import eyg/cli/helpers
import eyg/cli/overlay
import glasshouse/archive
import glasshouse/context
import glasshouse/journal
import glasshouse/rerun
import glasshouse/run
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/sandbox
import loam/sandbox/fs
import loam/source

const fields = [
  "append_file", "create_key", "cwd", "delete_file", "env", "fetch",
  "make_directory", "now", "read_directory", "read_file", "sign", "sleep",
  "standard_error", "standard_in", "standard_out", "write_file",
]

fn config() {
  let policy =
    list.map(fields, fn(field) { field <> ": (x) -> { Pass(x) }" })
    |> string.join(",\n    ")
  "let readme = match perform ReadFile({path: \"./README.md\", offset: 0, limit: 10000}) {
  Ok(bytes) -> { match !string_from_binary(bytes) { Ok(t) -> { t } Error(_) -> { \"\" } } }
  Error(_) -> { \"\" }
}
{
  llm: {provider: Ollama({origin: \"http://localhost:11434\", api_key: None({})}), model: \"test-model\"},
  policy: {
    "
  <> policy
  <> "
  },
  context: {readme}
}"
}

const tool_code =
  "match perform ReadFile({path: \"notes.txt\", offset: 0, limit: 100}) {
  Ok(bytes) -> { match !string_from_binary(bytes) { Ok(text) -> { text } Error(_) -> { \"\" } } }
  Error(reason) -> { reason }
}"

fn completion(message, prompt_tokens, completion_tokens) {
  json.object([
    #("message", message),
    #("prompt_eval_count", json.int(prompt_tokens)),
    #("eval_count", json.int(completion_tokens)),
    #("done", json.bool(True)),
  ])
  |> json.to_string
}

// The first request calls the run tool, after a tool result the model answers.
fn model(request: request.Request(BitArray), requests) {
  let assert "/api/chat" = request.path
  let assert Ok(body) = bit_array.to_string(request.body)
  let reply = case string.contains(body, "\"role\":\"tool\"") {
    False ->
      completion(
        json.object([
          #("role", json.string("assistant")),
          #("content", json.string("")),
          #(
            "tool_calls",
            json.preprocessed_array([
              json.object([
                #(
                  "function",
                  json.object([
                    #("name", json.string("run")),
                    #(
                      "arguments",
                      json.object([#("code", json.string(tool_code))]),
                    ),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
        120,
        30,
      )
    True ->
      completion(
        json.object([
          #("role", json.string("assistant")),
          #("content", json.string("The notes have two lines.")),
        ]),
        180,
        10,
      )
  }
  #(Ok(response.new(200) |> response.set_body(<<reply:utf8>>)), [
    request,
    ..requests
  ])
}

fn project() {
  sandbox.sandbox()
  |> sandbox.with_cwd("/project")
  |> sandbox.with_env("EYG_TRACE_DIR", "/traces")
  |> sandbox.with_now(1_791_889_260_000)
  |> sandbox.with_random_values([7])
  |> sandbox.with_files([
    #("/project/.overlay.eyg", config()),
    #("/project/README.md", "# Notes project\n"),
    #("/project/notes.txt", "line one\nline two\n"),
  ])
  |> sandbox.with_prompt_response(Ok("how many lines are in the notes?"))
  |> sandbox.with_network(model, [])
}

fn session_archive() {
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    overlay.execute(source.File(".overlay.eyg"), helpers.config)
    |> sandbox.run(project())
  let assert Ok(fs.Directory(children:, ..)) =
    fs.inspect(sandbox.file_system, "/traces")
  let assert [name] = dict.keys(children)
  let assert Ok(text) = fs.read(sandbox.file_system, "/traces/" <> name)
  let assert Ok(archive) = archive.from_string(text)
  #(archive, sandbox)
}

pub fn every_step_of_a_session_is_recorded_test() {
  let #(archive, sandbox) = session_archive()
  let events = archive.session.events
  let kinds =
    list.map(events, fn(event) {
      case event {
        session.Execution(run) -> run.kind_to_string(run.kind)
        session.Prompt(..) -> "prompt"
        session.Generated(..) -> "generation"
        session.ToolResult(..) -> "tool result"
      }
    })
  assert kinds
    == [
      "config", "prompt", "generation", "tool call", "tool result", "generation",
    ]
  let assert Some(agent) = archive.session.agent
  assert agent.provider == "ollama"
  assert agent.model == "test-model"
  assert string.contains(agent.system_prompt, "# Notes project")
  assert list.any(sandbox.stdout, fn(line) {
    string.contains(line, "trace saved to /traces/")
  })
  assert archive.missing(archive) == []
}

pub fn configuration_effects_are_recorded_test() {
  let #(archive, _) = session_archive()
  let assert [session.Execution(config), ..] = archive.session.events
  assert config.kind == run.Config
  let assert [read] = config.journal
  assert read.label == "ReadFile"
  assert read.path == Some("/project/README.md")
}

pub fn tool_calls_are_recorded_through_the_policy_test() {
  let #(archive, _) = session_archive()
  let assert [tool] =
    session.runs(archive.session)
    |> list.filter(fn(run) { run.kind == run.Tool("g1/0") })
  assert tool.code == tool_code
  let assert [read] = tool.journal
  assert read.answer == journal.Gated
  assert read.path == Some("/project/notes.txt")
  let assert [session.ToolResult(call_id: "g1/0", text:, ..)] =
    list.filter(archive.session.events, fn(event) {
      case event {
        session.ToolResult(..) -> True
        _ -> False
      }
    })
  assert string.contains(text, "line one")
}

pub fn generations_are_recorded_with_usage_test() {
  let #(archive, _) = session_archive()
  let assert [first, second] = session.generations(archive.session)
  assert first.usage == session.Usage(120, 30)
  assert second.usage == session.Usage(180, 10)
  assert second.content == "The notes have two lines."
  assert first.tool_calls
    == [
      session.ToolCall(
        "g1/0",
        "run",
        json.to_string(json.object([#("code", json.string(tool_code))])),
      ),
    ]
  // The exact request is stored, the second includes the tool result.
  let assert Ok(body) = store.get_binary(archive.store, second.request)
  let assert Ok(messages) = context.from_request(body)
  let assert [
    context.System(_),
    context.User(_),
    context.Assistant(..),
    context.Tool(_, result),
  ] = messages
  assert string.contains(result, "line one")
  assert first.key != second.key
}

pub fn a_recorded_session_replays_test() {
  let #(archive, _) = session_archive()
  let reports = rerun.session(archive.session, archive.store)
  assert list.length(reports) == 2
  assert list.all(reports, fn(report) { report.problem == None })
}
