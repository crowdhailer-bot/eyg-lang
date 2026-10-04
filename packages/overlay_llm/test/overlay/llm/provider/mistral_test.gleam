import gleam/bit_array
import gleam/http/response
import gleam/json
import gleam/string
import overlay/llm/chat
import overlay/llm/provider/mistral
import overlay/llm/tool

pub fn completion_request_test() {
  let request =
    mistral.completion_request(
      mistral.Config("key"),
      "mistral-small",
      "system",
      [chat.UserMessage("hi", [])],
      [],
    )
  assert request.host == "api.mistral.ai"
  assert request.path == "/v1/chat/completions"
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"stream\":false")
}

pub fn completion_response_test() {
  let body =
    json.object([
      #(
        "choices",
        json.preprocessed_array([
          json.object([
            #(
              "message",
              json.object([
                #("content", json.null()),
                #(
                  "tool_calls",
                  json.preprocessed_array([
                    json.object([
                      #("id", json.string("call1")),
                      #(
                        "function",
                        json.object([
                          #("name", json.string("run")),
                          #("arguments", json.string("{\"code\":\"1\"}")),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ])
    |> json.to_string
  let response = response.new(200) |> response.set_body(<<body:utf8>>)
  let assert Ok(chat.Completion(content: "", tool_calls: [call], ..)) =
    mistral.completion_response(response)
  let tool.Call(id:, function: tool.FunctionCall(name:, ..)) = call
  assert id == "call1"
  assert name == "run"
}

pub fn chunk_split_inside_character_test() {
  let line = "data: {\"choices\":[{\"delta\":{\"content\":\"é\"}}]}\n"
  let assert <<first:bytes-size(40), rest:bits>> = <<line:utf8>>
  let assert #([], remaining) = mistral.completion_chunk_parse(<<>>, first)
  let assert #([completion], <<>>) =
    mistral.completion_chunk_parse(remaining, rest)
  assert completion.content == "é"
}

pub fn unknown_content_chunk_is_ignored_test() {
  let line =
    "data: {\"choices\":[{\"delta\":{\"content\":[{\"type\":\"thinking\",\"thinking\":[]},{\"type\":\"text\",\"text\":\"hi\"}]}}]}\n"
  let assert #([completion], <<>>) =
    mistral.completion_chunk_parse(<<>>, <<line:utf8>>)
  assert completion.content == "hi"
}
