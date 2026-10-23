//// The screen as an étui frame. History rows carry what a click does and the
//// anchors that `Reveal` scrolls to.

import etui/buffer
import etui/geometry.{type Rect, Fill, Length, Vertical}
import etui/span
import etui/style
import etui/terminal
import etui/text
import eyg/cli/tui/editor.{type Editor}
import eyg/cli/tui/highlight as h
import eyg/cli/tui/model.{type Entry, type Model}
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

const help =
  "Enter run · Alt+Enter newline · Tab complete · Ctrl+E effects · PgUp/PgDn scroll · F1 close help
/scope bindings · /type expression · /help · /exit · Ctrl+C quit"

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
  let help = case model.help {
    True -> wrap(help, width - 4)
    False -> []
  }
  let choices = choices(model)
  let assert [header, history, help_area, choices_area, input, footer] =
    geometry.split(Vertical, inner, [
      Length(3),
      Fill,
      Length(case help {
        [] -> 0
        lines -> list.length(lines) + 2
      }),
      Length(case choices {
        [] -> 0
        choices -> list.length(choices) + 2
      }),
      Length(
        2
        + editor_height(model.editor)
        + case model.prompt {
          Some(_) -> 1
          None -> 0
        },
      ),
      Length(2),
    ])
  let heading = row(header, 1)
  let title = "eyg / tui"
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
      model.directory,
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
  let #(buf, cursor) = draw_input(buf, input, model)
  let buf =
    buf
    |> line(row(footer, 1), [#(model.status, h.muted)])
    |> right(row(footer, 1), "ctrl+e effects  ·  f1 help", h.muted)
  let frame = terminal.Frame(..frame, buffer: buf)
  #(terminal.set_cursor(frame, cursor), drawn)
}

// History

fn draw_history(buf, area: Rect, model: Model, top) {
  let width = area.size.width
  let rows = case model.entries {
    [] ->
      [
        #("Eat Your Greens", h.text),
        #("An expression. A useful result.", h.muted),
        #("Try @standard.integer.add(20, 22)", h.muted),
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
  let source = [blank(True), ..code_rows(entry.source, width - 4)]
  let output = case string.trim_end(entry.output) {
    "" -> []
    output -> [wrapped(output, h.muted, width - 4, False)]
  }
  let results =
    list.map(entry.results, fn(result) {
      case result {
        Ok(text) -> wrapped(text, h.accent, width - 4, False)
        Error(text) -> wrapped(text, h.red, width - 4, False)
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
            wrapped_at("↳ " <> effect.output, h.muted, width - 6, 4),
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
  list.flatten([source, [blank(True), blank(False)], body, [blank(False)]])
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
        plain(marker <> choice.label <> "  " <> choice.detail, color)
      })
    }
  }
}

// Input

/// Editor height in rows, between two and nine.
fn editor_height(editor: Editor) {
  int.clamp(list.length(string.split(editor.text, "\n")) + 1, 2, 9)
}

fn draw_input(buf, area: Rect, model: Model) {
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
  let #(buf, y) = case model.prompt {
    Some(#(prompt, _)) -> #(
      line(buf, geometry.rect_new(x, y, width, 1), [#(prompt, h.orange)]),
      y + 1,
    )
    None -> #(buf, y)
  }
  let height = editor_height(model.editor)
  let placeholder = case model.busy, model.prompt {
    True, None -> "You can draft while this runs…"
    _, _ -> "Write EYG…"
  }
  let #(buf, cursor) =
    draw_editor(
      buf,
      geometry.rect_new(x, y, width, height),
      model.editor,
      placeholder,
    )
  #(buf, cursor)
}

fn draw_editor(buf, area: Rect, edit: Editor, placeholder) {
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
      h.lines(source)
      |> list.flat_map(fn(parts) {
        list.map(parts, fn(part) {
          span.span_styled(part.0, foreground(part.1))
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
