import overlay/llm/chat
import overlay/llm/provider/ollama

fn event(content) {
  "{\"message\": {\"role\": \"assistant\", \"content\": \"" <> content <> "\"}}"
}

pub fn complete_lines_are_parsed_and_the_rest_kept_test() {
  let chunk = <<event("a"):utf8, "\n":utf8, "{\"mess":utf8>>
  let #(completions, remaining) = ollama.completion_chunk_parse(<<>>, chunk)
  assert completions
    == [chat.Completion(thinking: "", content: "a", tool_calls: [])]
  assert remaining == <<"{\"mess":utf8>>
}

pub fn empty_lines_are_skipped_test() {
  let chunk = <<event("a"):utf8, "\n\n":utf8, event("b"):utf8, "\n":utf8>>
  let #(completions, _) = ollama.completion_chunk_parse(<<>>, chunk)
  assert completions
    == [
      chat.Completion(thinking: "", content: "a", tool_calls: []),
      chat.Completion(thinking: "", content: "b", tool_calls: []),
    ]
}

pub fn a_line_that_is_not_an_event_is_skipped_test() {
  let chunk = <<"<html>Bad gateway</html>\n":utf8, event("a"):utf8, "\n":utf8>>
  let #(completions, _) = ollama.completion_chunk_parse(<<>>, chunk)
  assert completions
    == [chat.Completion(thinking: "", content: "a", tool_calls: [])]
}
