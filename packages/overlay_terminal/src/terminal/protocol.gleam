import gleam/dynamic/decode as d
import gleam/json as j
import gleam/list
import gleam/option.{type Option, None, Some}

pub type EffectRecord {
  EffectRecord(
    label: String,
    input: String,
    output: String,
    decision: Option(String),
  )
}

pub type Chunk {
  Chunk(
    text: String,
    token: String,
    selected: Bool,
    error: Bool,
    path: Option(List(Int)),
  )
}

pub type Input {
  Input(
    label: String,
    value: String,
    hints: List(#(String, String)),
    kind: String,
  )
}

pub type View {
  View(
    lines: List(List(Chunk)),
    source: String,
    type_: String,
    errors: List(String),
    message: Option(String),
    input: Option(Input),
  )
}

pub type Action {
  Enter(Option(String))
  Key(String)
  Answer(String)
  Paste(String)
  Focus(List(Int))
  Cancel
}

pub type Request {
  Initialize(List(String))
  Evaluate(id: Int, source: String, structural: Bool)
  Structure(Action)
  Reply(String)
}

pub type Event {
  Structural(View)
  Clipboard(String)
  Ready(List(String))
  OverlayReady(String)
  Assistant(id: Int, text: String)
  Tool(id: Int, name: String, code: String)
  ToolResult(id: Int, text: String, error: Bool, duration: Float)
  Packages(List(String))
  Output(id: Int, text: String, error: Bool)
  Effect(id: Int, effect: EffectRecord)
  Fetch(id: Int, url: String)
  Prompt(id: Int, text: String)
  Complete(
    id: Int,
    results: List(Result(String, String)),
    pending: String,
    duration: Float,
  )
  Failure(id: Int, message: String)
}

fn tag(name, fields) {
  j.object([#("type", j.string(name)), ..fields])
}

fn id_field(value) {
  #("id", j.int(value))
}

fn text_field(value) {
  #("text", j.string(value))
}

fn optional(name, value, encode) {
  case value {
    None -> []
    Some(value) -> [#(name, encode(value))]
  }
}

pub fn encode_request(request) {
  case request {
    Initialize(args) -> tag("initialize", [#("args", j.array(args, j.string))])
    Evaluate(id:, source:, structural:) ->
      tag("evaluate", [
        id_field(id),
        #("source", j.string(source)),
        #("structural", j.bool(structural)),
      ])
    Structure(action) -> {
      let #(name, fields) = case action {
        Enter(source) -> #("enter", optional("source", source, j.string))
        Key(key) -> #("key", [#("key", j.string(key))])
        Answer(value) -> #("answer", [text_field(value)])
        Paste(value) -> #("paste", [text_field(value)])
        Focus(path) -> #("focus", [#("path", j.array(path, j.int))])
        Cancel -> #("cancel", [])
      }
      tag("structure", [#("action", j.string(name)), ..fields])
    }
    Reply(value) -> tag("answer", [text_field(value)])
  }
}

pub fn request_decoder() {
  use type_ <- d.field("type", d.string)
  case type_ {
    "initialize" -> {
      use args <- d.field("args", d.list(d.string))
      d.success(Initialize(args))
    }
    "answer" -> {
      use value <- d.field("text", d.string)
      d.success(Reply(value))
    }
    "structure" -> {
      use action <- d.then(action_decoder())
      d.success(Structure(action))
    }
    "evaluate" -> {
      use id <- d.field("id", d.int)
      use source <- d.field("source", d.string)
      use structural <- d.optional_field("structural", False, d.bool)
      d.success(Evaluate(id, source, structural))
    }
    _ -> d.failure(Reply(""), "terminal request")
  }
}

fn action_decoder() {
  use action <- d.field("action", d.string)
  case action {
    "enter" -> {
      use source <- d.optional_field("source", None, d.optional(d.string))
      d.success(Enter(source))
    }
    "key" -> {
      use key <- d.field("key", d.string)
      d.success(Key(key))
    }
    "answer" -> {
      use value <- d.field("text", d.string)
      d.success(Answer(value))
    }
    "paste" -> {
      use value <- d.field("text", d.string)
      d.success(Paste(value))
    }
    "focus" -> {
      use path <- d.field("path", d.list(d.int))
      d.success(Focus(path))
    }
    "cancel" -> d.success(Cancel)
    _ -> d.failure(Cancel, "structural action")
  }
}

pub fn encode_event(event) {
  case event {
    Structural(view) -> tag("structure", [#("view", encode_view(view))])
    Clipboard(value) -> tag("clipboard", [text_field(value)])
    Ready(packages) ->
      tag("ready", [#("packages", j.array(packages, j.string))])
    OverlayReady(model) -> tag("overlay-ready", [#("model", j.string(model))])
    Assistant(id:, text:) -> tag("assistant", [id_field(id), text_field(text)])
    Tool(id:, name:, code:) ->
      tag("tool", [
        id_field(id),
        #("name", j.string(name)),
        #("code", j.string(code)),
      ])
    ToolResult(id:, text:, error:, duration:) ->
      tag("tool-result", [
        id_field(id),
        text_field(text),
        #("error", j.bool(error)),
        #("duration", j.float(duration)),
      ])
    Packages(packages) ->
      tag("packages", [#("packages", j.array(packages, j.string))])
    Output(id:, text:, error:) ->
      tag("output", [id_field(id), text_field(text), #("error", j.bool(error))])
    Effect(id:, effect:) ->
      tag("effect", [id_field(id), #("effect", encode_effect(effect))])
    Fetch(id:, url:) -> tag("fetch", [id_field(id), #("url", j.string(url))])
    Prompt(id:, text:) -> tag("prompt", [id_field(id), text_field(text)])
    Complete(id:, results:, pending:, duration:) ->
      tag("complete", [
        id_field(id),
        #("results", j.array(results, encode_result)),
        #("pending", j.string(pending)),
        #("duration", j.float(duration)),
      ])
    Failure(id:, message:) ->
      tag("error", [id_field(id), #("message", j.string(message))])
  }
}

fn encode_effect(effect: EffectRecord) {
  j.object([
    #("label", j.string(effect.label)),
    #("input", j.string(effect.input)),
    #("output", j.string(effect.output)),
    ..optional("decision", effect.decision, j.string)
  ])
}

fn encode_result(result) {
  case result {
    Ok(value) -> j.object([text_field(value), #("error", j.bool(False))])
    Error(value) -> j.object([text_field(value), #("error", j.bool(True))])
  }
}

fn encode_chunk(chunk: Chunk) {
  j.object([
    text_field(chunk.text),
    #("token", j.string(chunk.token)),
    #("selected", j.bool(chunk.selected)),
    #("error", j.bool(chunk.error)),
    ..optional("path", chunk.path, j.array(_, j.int))
  ])
}

fn encode_input(input: Input) {
  j.object([
    #("label", j.string(input.label)),
    #("value", j.string(input.value)),
    #("kind", j.string(input.kind)),
    #(
      "hints",
      j.array(input.hints, fn(pair) { j.array([pair.0, pair.1], j.string) }),
    ),
  ])
}

fn encode_view(view: View) {
  j.object(
    list.flatten([
      [
        #("lines", j.array(view.lines, j.array(_, encode_chunk))),
        #("source", j.string(view.source)),
        #("type", j.string(view.type_)),
        #("errors", j.array(view.errors, j.string)),
      ],
      optional("message", view.message, j.string),
      optional("input", view.input, encode_input),
    ]),
  )
}

pub fn event_decoder() {
  use type_ <- d.field("type", d.string)
  case type_ {
    "structure" -> {
      use view <- d.field("view", view_decoder())
      d.success(Structural(view))
    }
    "clipboard" -> {
      use value <- d.field("text", d.string)
      d.success(Clipboard(value))
    }
    "ready" | "packages" -> {
      use packages <- d.field("packages", d.list(d.string))
      d.success(case type_ {
        "ready" -> Ready(packages)
        _ -> Packages(packages)
      })
    }
    "overlay-ready" -> {
      use model <- d.field("model", d.string)
      d.success(OverlayReady(model))
    }
    _ -> {
      use id <- d.field("id", d.int)
      event_with_id(type_, id)
    }
  }
}

fn event_with_id(type_, id) {
  case type_ {
    "assistant" -> {
      use value <- d.field("text", d.string)
      d.success(Assistant(id, value))
    }
    "tool" -> {
      use name <- d.field("name", d.string)
      use code <- d.field("code", d.string)
      d.success(Tool(id, name, code))
    }
    "tool-result" -> {
      use value <- d.field("text", d.string)
      use error <- d.field("error", d.bool)
      use duration <- d.field("duration", d.float)
      d.success(ToolResult(id, value, error, duration))
    }
    "output" -> {
      use value <- d.field("text", d.string)
      use error <- d.optional_field("error", False, d.bool)
      d.success(Output(id, value, error))
    }
    "effect" -> {
      use effect <- d.field("effect", effect_decoder())
      d.success(Effect(id, effect))
    }
    "fetch" -> {
      use url <- d.field("url", d.string)
      d.success(Fetch(id, url))
    }
    "prompt" -> {
      use value <- d.field("text", d.string)
      d.success(Prompt(id, value))
    }
    "complete" -> {
      use results <- d.field("results", d.list(result_decoder()))
      use pending <- d.field("pending", d.string)
      use duration <- d.field("duration", d.float)
      d.success(Complete(id, results, pending, duration))
    }
    "error" -> {
      use message <- d.field("message", d.string)
      d.success(Failure(id, message))
    }
    _ -> d.failure(Failure(id, ""), "terminal event")
  }
}

fn effect_decoder() {
  use label <- d.field("label", d.string)
  use input <- d.field("input", d.string)
  use output <- d.field("output", d.string)
  use decision <- d.optional_field("decision", None, d.optional(d.string))
  d.success(EffectRecord(label, input, output, decision))
}

fn result_decoder() {
  use value <- d.field("text", d.string)
  use error <- d.field("error", d.bool)
  d.success(case error {
    True -> Error(value)
    False -> Ok(value)
  })
}

fn view_decoder() {
  use lines <- d.field("lines", d.list(d.list(chunk_decoder())))
  use source <- d.field("source", d.string)
  use type_ <- d.field("type", d.string)
  use errors <- d.field("errors", d.list(d.string))
  use message <- d.optional_field("message", None, d.optional(d.string))
  use input <- d.optional_field("input", None, d.optional(input_decoder()))
  d.success(View(lines, source, type_, errors, message, input))
}

fn chunk_decoder() {
  use value <- d.field("text", d.string)
  use token <- d.optional_field("token", "", d.string)
  use selected <- d.optional_field("selected", False, d.bool)
  use error <- d.optional_field("error", False, d.bool)
  use path <- d.optional_field("path", None, d.optional(d.list(d.int)))
  d.success(Chunk(value, token, selected, error, path))
}

fn input_decoder() {
  use label <- d.field("label", d.string)
  use value <- d.field("value", d.string)
  use kind <- d.field("kind", d.string)
  use hints <- d.field("hints", d.list(pair_decoder()))
  d.success(Input(label, value, hints, kind))
}

fn pair_decoder() {
  use a <- d.then(d.at([0], d.string))
  use b <- d.then(d.at([1], d.string))
  d.success(#(a, b))
}
