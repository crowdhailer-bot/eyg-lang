import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{None, Some}
import gleam/result

pub type Highlighter

pub type Token {
  Token(content: String, color: String)
}

pub type Highlight {
  Highlight(lines: List(List(Token)), foreground: String)
}

@external(javascript, "./shiki_ffi.mjs", "create")
pub fn create(grammar: String) -> Promise(Result(Highlighter, String))

@external(javascript, "./shiki_ffi.mjs", "tokens")
fn tokens(
  highlighter: Highlighter,
  source: String,
  language: String,
  theme: String,
) -> Result(Dynamic, String)

pub fn highlight(highlighter, source, language, theme) {
  use raw <- result.try(tokens(highlighter, source, language, theme))
  let decoder = {
    use foreground <- decode.optional_field("fg", "#e1e4e8", decode.string)
    use lines <- decode.field(
      "tokens",
      decode.list(
        decode.list({
          use content <- decode.field("content", decode.string)
          use color <- decode.optional_field(
            "color",
            None,
            decode.optional(decode.string),
          )
          decode.success(
            Token(content, case color {
              Some(color) -> color
              None -> foreground
            }),
          )
        }),
      ),
    )
    decode.success(Highlight(lines, foreground))
  }
  decode.run(raw, decoder)
  |> result.replace_error("Unable to decode Shiki tokens")
}
