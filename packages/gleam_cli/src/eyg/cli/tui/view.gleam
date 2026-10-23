//// The screen as an étui frame. History rows carry what a click does and the
//// anchors that `Reveal` scrolls to.

import etui/buffer
import etui/geometry.{type Rect, Fill, Length, Vertical}
import etui/span
import etui/style
import etui/terminal
import etui/text
import eyg/cli/tui/agent
import eyg/cli/tui/editor.{type Editor}
import eyg/cli/tui/highlight as h
import eyg/cli/tui/model.{type Entry, type Model}
import eyg/cli/tui/projection
import eyg/cli/tui/structural
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

type Row {
  Row(
    line: span.Line,
    panel: Bool,
    click: Option(model.Click),
    anchor: Option(String),
  )
}

pub type Drawn {
  Drawn(
    clicks: List(#(Rect, model.Click)),
    anchors: List(#(String, Int)),
    history: Rect,
    total: Int,
    top: Int,
  )
}

pub fn empty() {
  Drawn([], [], geometry.rect_new(0, 0, 0, 0), 0, 0)
}

const overlay_help =
  "Enter send · Alt+Enter newline · Ctrl+E effects · Ctrl+O code · PgUp/PgDn scroll · F1 close help
/export <file> chat · /exit · Ctrl+C quit"

const help =
  "Enter run · Alt+Enter newline · Tab complete · Ctrl+E effects · PgUp/PgDn scroll · F1 close help
/scope bindings · /type expression · /help · /exit · Ctrl+C quit
F2 text/structure · arrows navigate · Space vacant · a select parent · i edit · d delete · z/Z undo/redo
n integer · s string · b binary · v variable · f function · c/C/w call · e/E let · l/L list · r/R record
g field · o overwrite · t tag · m match · p/h effects · j builtin · @/# reference · q/Q file · x spread
y/Y copy/paste · k fold · </> insert before/after · Enter evaluate · Escape dismiss / text"

/// `top` is the first history row shown, `None` follows the newest output.
pub fn draw(
  frame: terminal.Frame,
  model: Model,
  top: Option(Int),
) -> #(terminal.Frame, Drawn) {
  let area = frame.area
  let buf = buffer.set_style(frame.buffer, area, background(h.bg))
  let inner = pad_x(area, 2)
  let width = inner.size.width
  let help = case model.help, model.overlay {
    True, True -> wrap(overlay_help, width - 4)
    True, False -> wrap(help, width - 4)
    False, _ -> []
  }
  let choices = choices(model)
  let structure = case model.structural, model.structure {
    True, Some(structure) -> Some(structure_view(structure))
    _, _ -> None
  }
  let label = label(model)
  let assert [
    header,
    history,
    help_area,
    structure_area,
    choices_area,
    input,
    footer,
  ] =
    geometry.split(Vertical, inner, [
      Length(3),
      Fill,
      Length(case help {
        [] -> 0
        lines -> list.length(lines) + 2
      }),
      Length(case structure {
        Some(view) -> structure_height(view)
        None -> 0
      }),
      Length(case choices {
        [] -> 0
        choices -> list.length(choices) + 2
      }),
      Length(case model.editing_text(model), label {
        False, _ -> 0
        True, None -> 2 + editor_height(model.editor)
        True, Some(_) -> 3 + editor_height(model.editor)
      }),
      Length(2),
    ])
  let heading = row(header, 1)
  let #(title, context) = case model.overlay, model.agent {
    True, Some(running) -> #(
      "eyg / overlay",
      model.directory <> "  ·  " <> agent.model_name(running),
    )
    True, None -> #("eyg / overlay", model.directory)
    False, _ -> #("eyg / tui", model.directory)
  }
  let after = text.cell_width(title) + 2
  let buf =
    buf
    |> line(heading, [#(title, h.accent)])
    |> right(
      geometry.rect_new(
        heading.position.x + after,
        heading.position.y,
        int.max(0, heading.size.width - after),
        1,
      ),
      context,
      h.muted,
    )
  let #(buf, drawn) = draw_history(buf, history, model, top)
  let buf = case help {
    [] -> buf
    lines ->
      panel(buf, help_area)
      |> lines_at(inset(help_area, 2, 1), list.map(lines, plain(_, h.muted)))
  }
  let buf = case choices {
    [] -> buf
    choices ->
      panel(buf, choices_area)
      |> lines_at(inset(choices_area, 2, 1), choices)
  }
  let #(buf, focus) = case structure {
    Some(view) -> draw_structure(buf, structure_area, view)
    None -> #(buf, [])
  }
  let #(buf, cursor) = case model.editing_text(model) {
    True -> {
      let #(buf, cursor) = draw_input(buf, input, model, label)
      #(buf, Some(cursor))
    }
    False -> #(buf, None)
  }
  let mode = case model.overlay, model.structural {
    True, _ -> "ctrl+o code"
    False, True -> "f2 text"
    False, False -> "f2 structure"
  }
  let buf =
    buf
    |> line(row(footer, 1), [#(model.status, h.muted)])
    |> right(row(footer, 1), mode <> "  ·  ctrl+e effects  ·  f1 help", h.muted)
  let frame = terminal.Frame(..frame, buffer: buf)
  let frame = case cursor {
    Some(cursor) -> terminal.set_cursor(frame, cursor)
    None -> terminal.hide_cursor(frame)
  }
  #(frame, Drawn(..drawn, clicks: list.append(drawn.clicks, focus)))
}

// History

fn draw_history(buf, area: Rect, model: Model, top) {
  let width = area.size.width
  let rows = case model.entries {
    [] ->
      [
        #("Eat Your Greens", h.text),
        case model.overlay {
          True -> #("An agent with tools you can inspect.", h.muted)
          False -> #("An expression. A useful result.", h.muted)
        },
        case model.overlay {
          True -> #(
            "Ask a question or describe a task to get started.",
            h.muted,
          )
          False -> #("Try @standard.integer.add(20, 22)", h.muted)
        },
      ]
      |> list.map(fn(intro) { wrapped(intro.0, intro.1, width - 4, False) })
      |> list.intersperse([blank(False)])
      |> list.flatten
      |> list.append([blank(False), blank(False), blank(False)], _)
    entries -> list.flat_map(entries, entry(_, width))
  }
  let total = list.length(rows)
  let height = area.size.height
  let last = int.max(0, total - height)
  let top = case top {
    None -> last
    Some(top) -> int.clamp(top, 0, last)
  }
  let #(buf, clicks, _) =
    rows
    |> list.drop(top)
    |> list.take(height)
    |> list.fold(#(buf, [], 0), fn(acc, row) {
      let #(buf, clicks, index) = acc
      let rect =
        geometry.rect_new(area.position.x, area.position.y + index, width, 1)
      let buf = case row.panel {
        True -> buffer.set_style(buf, rect, background(h.panel))
        False -> buf
      }
      let buf = span.render_line(buf, rect.position, row.line, width)
      let clicks = case row.click {
        Some(click) -> [#(rect, click), ..clicks]
        None -> clicks
      }
      #(buf, clicks, index + 1)
    })
  let anchors =
    list.index_fold(rows, [], fn(anchors, row, index) {
      case row.anchor {
        Some(anchor) -> [#(anchor, index), ..anchors]
        None -> anchors
      }
    })
  #(buf, Drawn(clicks:, anchors:, history: area, total:, top:))
}

fn entry(entry: Entry, width) -> List(Row) {
  let id = int.to_string(entry.id)
  let source = case entry.role, entry.code_expanded {
    model.Assistant, _ -> []
    model.User, _ -> wrapped(entry.source, h.text, width - 4, True)
    model.Repl, _ -> code_rows(entry.source, width - 4)
    model.Tool, expanded -> [
      Row(
        ..text_row(tool_title(entry), h.blue, 2, True),
        click: Some(model.ToggleCode(entry.id)),
        anchor: Some("code-" <> id),
      ),
      ..case expanded {
        True -> code_rows(entry.source, width - 4)
        False -> []
      }
    ]
  }
  let source = case source {
    [] -> []
    rows -> list.flatten([[blank(True)], rows, [blank(True), blank(False)]])
  }
  // A tool reports its output with its result.
  let output = case entry.role, string.trim_end(entry.output) {
    _, "" -> []
    model.Tool, _ if entry.results != [] -> []
    model.Assistant, text -> [wrapped(text, h.text, width - 4, False)]
    _, text -> [wrapped(text, h.muted, width - 4, False)]
  }
  let results =
    list.map(entry.results, fn(result) {
      let #(text, color) = case result {
        Ok(text) -> #(text, h.accent)
        Error(text) -> #(text, h.red)
      }
      let lines = string.split(text, "\n")
      let long = entry.role == model.Tool && list.length(lines) > 8
      case long, entry.output_expanded {
        False, _ -> wrapped(text, color, width - 4, False)
        True, True ->
          list.append(wrapped(text, color, width - 4, False), [
            Row(
              ..text_row("▾ Collapse output", h.muted, 2, False),
              click: Some(model.ToggleOutput(entry.id)),
            ),
          ])
        True, False -> {
          let shown = list.take(lines, 8) |> string.join("\n")
          let toggle =
            "▸ Show all " <> int.to_string(list.length(lines)) <> " lines"
          list.append(wrapped(shown, color, width - 4, False), [
            Row(
              ..text_row(toggle, h.muted, 2, False),
              click: Some(model.ToggleOutput(entry.id)),
            ),
          ])
        }
      }
    })
  let running = case entry.busy {
    True -> [[text_row("● Running…", h.muted, 2, False)]]
    False -> []
  }
  let effects = case model.has_effects(entry) {
    False -> []
    True -> [
      [
        Row(
          ..text_row(effects_summary(entry), h.muted, 2, False),
          click: Some(model.ToggleEffects(entry.id)),
          anchor: Some("effects-" <> id),
        ),
      ],
    ]
  }
  let details = case entry.expanded {
    False -> []
    True -> [
      list.flatten([
        list.map(entry.fetches, fn(url) {
          text_row("↓ " <> url, h.blue, 2, False)
        }),
        list.flat_map(entry.performed, fn(effect) {
          list.append(
            wrapped_at(
              effect.label <> "(" <> effect.input <> ")",
              h.orange,
              width - 6,
              4,
            ),
            wrapped_at(
              "↳ "
                <> case effect.decision {
                Some(decision) -> decision <> " · "
                None -> ""
              }
                <> effect.output,
              h.muted,
              width - 6,
              4,
            ),
          )
        }),
      ])
      |> anchor_first("details-" <> id),
    ]
  }
  let body =
    [output, results, running, effects, details]
    |> list.flatten
    |> list.intersperse([blank(False)])
    |> list.flatten
  list.flatten([source, body, [blank(False)]])
}

fn tool_title(entry: Entry) {
  case entry.code_expanded {
    True -> "▾ "
    False -> "▸ "
  }
  <> entry.name
  <> "  "
  <> case entry.duration {
    None -> "running"
    Some(duration) -> int.to_string(float.round(duration)) <> " ms"
  }
  <> " · code"
}

fn effects_summary(entry: Entry) {
  let fetches = list.length(entry.fetches)
  case entry.expanded {
    True -> "▾ "
    False -> "▸ "
  }
  <> int.to_string(list.length(entry.performed))
  <> " effects"
  <> case fetches {
    0 -> ""
    _ -> " · " <> int.to_string(fetches) <> " hub requests"
  }
  <> case entry.duration {
    None -> ""
    Some(duration) -> "  " <> int.to_string(float.round(duration)) <> " ms"
  }
}

fn anchor_first(rows, anchor) {
  case rows {
    [first, ..rest] -> [Row(..first, anchor: Some(anchor)), ..rest]
    [] -> []
  }
}

fn blank(panel) {
  Row(span.line_new([]), panel, None, None)
}

fn text_row(text, color, indent, panel) {
  Row(
    span.line_new([
      span.span_plain(string.repeat(" ", indent)),
      span.span_styled(text, foreground(color)),
    ]),
    panel,
    None,
    None,
  )
}

fn wrapped(text, color, width, panel) -> List(Row) {
  wrap(text, width) |> list.map(text_row(_, color, 2, panel))
}

fn wrapped_at(text, color, width, indent) -> List(Row) {
  wrap(text, width) |> list.map(text_row(_, color, indent, False))
}

fn wrap(text, width) {
  string.split(text, "\n")
  |> list.flat_map(fn(line) {
    case line {
      "" -> [""]
      _ -> text.wrap(line, int.max(1, width))
    }
  })
}

fn code_rows(source, width) {
  h.lines(source)
  |> list.flat_map(fn(parts) {
    list.map(parts, fn(part) { span.span_styled(part.0, foreground(part.1)) })
    |> span.line_new
    |> span.wrap_line(int.max(1, width))
  })
  |> list.map(fn(line) {
    Row(span.line_new([span.span_plain("  "), ..line.spans]), True, None, None)
  })
}

// Structure

type StructureView {
  StructureView(
    lines: List(List(projection.Chunk)),
    type_: String,
    errors: List(String),
  )
}

fn structure_view(structure: model.Structure) {
  let #(type_, errors) = structural.type_info(structure.buffer)
  let one_line = fn(text) {
    string.split(text, "\n") |> list.map(string.trim) |> string.join(" ")
  }
  StructureView(
    lines: projection.project([structural.view(structure.buffer)]),
    type_: case type_ {
      "" -> "n integer · s string · @ package · F1 all shortcuts"
      type_ -> one_line(type_)
    },
    errors: list.take(errors, 2) |> list.map(one_line),
  )
}

fn tree_height(view: StructureView) {
  int.clamp(list.length(view.lines), 2, 12)
}

fn structure_height(view: StructureView) {
  3 + tree_height(view) + list.length(view.errors)
}

/// The projection, scrolled to keep the selection in view, then its type and
/// errors. Each chunk with a path focuses that expression when clicked.
fn draw_structure(buf, area: Rect, view: StructureView) {
  let buf = panel(buf, area)
  let content = inset(area, 2, 1)
  let height = tree_height(view)
  let selected =
    list.index_fold(view.lines, -1, fn(found, line, index) {
      case found == -1 && list.any(line, fn(chunk) { chunk.selected }) {
        True -> index
        False -> found
      }
    })
  let first = int.clamp(selected - height + 1, 0, int.max(0, selected))
  let #(buf, clicks) =
    view.lines
    |> list.drop(first)
    |> list.take(height)
    |> list.index_fold(#(buf, []), fn(acc, chunks, index) {
      let y = content.position.y + index
      let #(buf, clicks, _) =
        list.fold(chunks, #(acc.0, acc.1, content.position.x), fn(acc, chunk) {
          let #(buf, clicks, x) = acc
          let chunk_style = case chunk.selected {
            True -> style.new(colour(h.bg), colour(h.accent), style.none())
            False -> foreground(token_colour(chunk.token))
          }
          let chunk_style = case chunk.error {
            True ->
              style.with_modifier(
                chunk_style,
                style.add(chunk_style.modifier, style.underline()),
              )
            False -> chunk_style
          }
          let cells = text.cell_width(chunk.text)
          let buf =
            span.render_line(
              buf,
              geometry.Position(x:, y:),
              span.line_new([span.span_styled(chunk.text, chunk_style)]),
              content.position.x + content.size.width - x,
            )
          let clicks = case chunk.path {
            Some(path) -> [
              #(geometry.rect_new(x, y, cells, 1), model.Focus(path)),
              ..clicks
            ]
            None -> clicks
          }
          #(buf, clicks, x + cells)
        })
      #(buf, clicks)
    })
  let below = content.position.y + height
  let buf =
    line(
      buf,
      geometry.rect_new(content.position.x, below, content.size.width, 1),
      [#(view.type_, h.muted)],
    )
    |> lines_at(
      geometry.rect_new(
        content.position.x,
        below + 1,
        content.size.width,
        list.length(view.errors),
      ),
      list.map(view.errors, plain(_, h.red)),
    )
  #(buf, clicks)
}

/// Morph's token classes in the colours of highlighted text.
fn token_colour(token) {
  case token {
    "comment" -> h.muted
    "string" | "char" -> h.accent
    "reference" | "builtin" | "symbol" -> h.blue
    "number" | "tag" | "class-name" -> h.orange
    "keyword" -> h.purple
    "important" -> h.red
    _ -> h.text
  }
}

/// What the editor is answering: a program's prompt or a structural edit.
fn label(model: Model) {
  case model.prompt, model.input(model) {
    Some(#(prompt, _)), _ -> Some(#(prompt, h.orange))
    None, Some(input) ->
      Some(#(input.label <> " · Enter confirm · Escape cancel", h.blue))
    None, None -> None
  }
}

/// At most six completion choices around the selected one.
fn choices(model: Model) {
  case model.busy {
    True -> []
    False -> {
      let start = int.max(0, model.choice - 5)
      model.choices
      |> list.drop(start)
      |> list.take(6)
      |> list.index_map(fn(choice, index) {
        let #(marker, color) = case start + index == model.choice {
          True -> #("› ", h.accent)
          False -> #("  ", h.muted)
        }
        let detail = string.replace(choice.detail, "\n", " ")
        plain(marker <> choice.label <> "  " <> detail, color)
      })
    }
  }
}

// Input

/// Editor height in rows, between two and nine.
fn editor_height(editor: Editor) {
  int.clamp(list.length(string.split(editor.text, "\n")) + 1, 2, 9)
}

fn draw_input(buf, area: Rect, model: Model, label) {
  let buf = panel(buf, area)
  let buf =
    list.repeat(Nil, area.size.height)
    |> list.index_fold(buf, fn(buf, _, offset) {
      buffer.set_string(
        buf,
        geometry.Position(area.position.x, area.position.y + offset),
        "│",
        style.new(colour(h.accent), colour(h.panel), style.none()),
      )
    })
  let x = area.position.x + 3
  let width = int.max(0, area.size.width - 5)
  let y = area.position.y + 1
  let #(buf, y) = case label {
    Some(label) -> #(
      line(buf, geometry.rect_new(x, y, width, 1), [label]),
      y + 1,
    )
    None -> #(buf, y)
  }
  let height = editor_height(model.editor)
  let placeholder = case model.busy, model.prompt, model.overlay {
    True, None, _ -> "You can draft while this runs…"
    _, None, True -> "Ask anything…"
    _, _, _ -> "Write EYG…"
  }
  let #(buf, cursor) =
    draw_editor(
      buf,
      geometry.rect_new(x, y, width, height),
      model.editor,
      placeholder,
      !model.overlay,
    )
  #(buf, cursor)
}

fn draw_editor(buf, area: Rect, edit: Editor, placeholder, highlight) {
  let width = int.max(1, area.size.width)
  let #(line_index, column) = editor.position(edit)
  let source_lines = string.split(edit.text, "\n")
  // Rows before the cursor's line, wrapped by cell width.
  let before =
    source_lines
    |> list.take(line_index)
    |> list.fold(0, fn(rows, line) {
      rows + int.max(1, { text.cell_width(line) + width - 1 } / width)
    })
  let current = case list.drop(source_lines, line_index) {
    [line, ..] -> line
    [] -> ""
  }
  let cells = text.cell_width(string.slice(current, 0, column))
  let cursor_row = before + cells / width
  let first = int.max(0, cursor_row - area.size.height + 1)
  let rows = case edit.text {
    "" -> [plain(placeholder, h.muted)]
    source ->
      case highlight {
        True -> h.lines(source)
        False ->
          string.split(source, "\n") |> list.map(fn(line) { [#(line, h.text)] })
      }
      |> list.flat_map(fn(parts) {
        list.map(parts, fn(part) {
          span.span_styled(part.0, case edit.selected {
            True -> style.new(colour(h.panel), colour(h.text), style.none())
            False -> foreground(part.1)
          })
        })
        |> span.line_new
        |> cut(width)
      })
  }
  let buf =
    lines_at(
      buf,
      geometry.rect_new(
        area.position.x,
        area.position.y,
        width,
        area.size.height,
      ),
      list.drop(rows, first),
    )
  let cursor =
    geometry.Position(
      area.position.x + cells % width,
      area.position.y + cursor_row - first,
    )
  #(buf, cursor)
}

/// Break a line at the width without moving words, so the cursor column is
/// the cell offset modulo the width.
fn cut(line: span.Line, width) -> List(span.Line) {
  let graphemes =
    list.flat_map(line.spans, fn(sp: span.Span) {
      text.graphemes(sp.content) |> list.map(fn(g) { #(g, sp.style) })
    })
  let #(rows, current, _) =
    list.fold(graphemes, #([], [], 0), fn(acc, grapheme) {
      let #(rows, current, used) = acc
      let cells = text.grapheme_cell_width(grapheme.0)
      case used + cells > width {
        True -> #([list.reverse(current), ..rows], [grapheme], cells)
        False -> #(rows, [grapheme, ..current], used + cells)
      }
    })
  [list.reverse(current), ..rows]
  |> list.reverse
  |> list.map(fn(row) {
    span.line_new(list.map(row, fn(g) { span.span_styled(g.0, g.1) }))
  })
}

// Drawing helpers

fn colour(hex: String) -> style.Color {
  let channel = fn(offset) {
    let assert Ok(value) = int.base_parse(string.slice(hex, offset, 2), 16)
    value
  }
  style.Rgb(channel(1), channel(3), channel(5))
}

fn foreground(hex) {
  style.default_style() |> style.with_fg(colour(hex))
}

fn background(hex) {
  style.default_style() |> style.with_bg(colour(hex))
}

fn plain(text, color) {
  span.line_new([span.span_styled(text, foreground(color))])
}

fn line(buf, area: Rect, parts: List(#(String, String))) {
  span.render_line(
    buf,
    area.position,
    span.line_new(
      list.map(parts, fn(part) { span.span_styled(part.0, foreground(part.1)) }),
    ),
    area.size.width,
  )
}

fn right(buf, area: Rect, text, color) {
  span.render_line(
    buf,
    area.position,
    span.line_aligned([span.span_styled(text, foreground(color))], text.Right),
    area.size.width,
  )
}

fn lines_at(buf, area: Rect, lines: List(span.Line)) {
  lines
  |> list.take(area.size.height)
  |> list.index_fold(buf, fn(buf, line, index) {
    span.render_line(
      buf,
      geometry.Position(area.position.x, area.position.y + index),
      line,
      area.size.width,
    )
  })
}

fn panel(buf, area) {
  buffer.set_style(buf, area, background(h.panel))
}

fn row(area: Rect, offset) {
  geometry.rect_new(
    area.position.x,
    area.position.y + offset,
    area.size.width,
    1,
  )
}

fn pad_x(area: Rect, padding) {
  geometry.rect_new(
    area.position.x + padding,
    area.position.y,
    int.max(0, area.size.width - 2 * padding),
    area.size.height,
  )
}

fn inset(area: Rect, x, y) {
  geometry.rect_new(
    area.position.x + x,
    area.position.y + y,
    int.max(0, area.size.width - 2 * x),
    int.max(0, area.size.height - 2 * y),
  )
}
