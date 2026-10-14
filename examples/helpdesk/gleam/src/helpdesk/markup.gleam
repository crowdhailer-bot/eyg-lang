import gleam/string

pub type Body

pub fn inject(content_types: List(String), body: Body) -> Body {
  case content_types {
    [content_type] ->
      case string.starts_with(content_type, "text/html") {
        True -> {
          string.replace(
            body_text(body),
            "</html>",
            "<script type=\"module\" src=\"/assets/admin_eyg.js\"></script></html>",
          )
          |> as_body
        }
        False -> body
      }
    _ -> body
  }
}

@external(erlang, "Elixir.Helpdesk.EygBridge", "body_text")
fn body_text(body: Body) -> String

@external(erlang, "Elixir.Helpdesk.EygBridge", "identity")
fn as_body(text: String) -> Body
