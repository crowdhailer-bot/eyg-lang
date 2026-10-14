//// Scripted Ollama for the checked terminal walkthrough. No remote model or credentials.

import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub fn main() {
  let assert Ok(_) = start()
  io.println("Scripted terminal model listening on http://127.0.0.1:7206")
}

pub fn start() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7206, "127.0.0.1", fn(request) {
      use body <- promise.map(fetch.request_text(request))
      let assert Ok(body) = body
      let content = case
        string.contains(fetch.request_url(request), "/api/chat")
      {
        True -> completion(body)
        False -> "[]"
      }
      let assert Ok(response) =
        fetch.new_response(response, content, 200, [
          #("content-type", "application/x-ndjson"),
        ])
      response
    }),
  )
}

fn completion(body) {
  let assert Ok(roles) =
    json.parse(
      body,
      decode.field(
        "messages",
        decode.list(decode.field("role", decode.string, decode.success)),
        decode.success,
      ),
    )
  let assert Ok(last) = list.last(roles)
  let calls = case last {
    "tool" -> []
    _ -> [
      json.object([
        #(
          "function",
          json.object([
            #("name", json.string("run")),
            #(
              "arguments",
              json.object([
                #(
                  "code",
                  json.string(
                    "let _ = perform StandardOut(\"Hello from Gleam\") !int_add(20, 22)",
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ]
  }
  json.object([
    #(
      "message",
      json.object([
        #("role", json.string("assistant")),
        #(
          "content",
          json.string(case calls {
            [] -> "Computed **42** and printed the greeting."
            _ -> "I will run the calculation."
          }),
        ),
        #("tool_calls", json.preprocessed_array(calls)),
      ]),
    ),
    #("done", json.bool(True)),
    #("prompt_eval_count", json.int(20)),
    #("eval_count", json.int(10)),
  ])
  |> json.to_string
  |> string.append("\n")
}
