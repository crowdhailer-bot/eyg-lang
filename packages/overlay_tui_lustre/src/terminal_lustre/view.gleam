import core/native as n
import core/native_view
import gleam/dynamic/decode
import gleam/int
import gleam/json as j
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as at
import lustre/element as e
import lustre/element/keyed
import lustre/event
import plinthx/bun
import terminal/app as a
import terminal/highlight as h
import terminal/protocol as p

pub fn options(properties) {
  at.property("options", j.object(properties))
}

pub fn str(name, value) {
  at.property(name, j.string(value))
}

pub fn boolean(name, value) {
  at.property(name, j.bool(value))
}

pub fn number(name, value) {
  at.property(name, j.int(value))
}

pub fn box(properties, attributes, children) {
  e.element(
    "box",
    [options([n.s("flexDirection", "column"), ..properties]), ..attributes],
    children,
  )
}

pub fn text(content, color, properties, attributes) {
  e.element(
    "text",
    [
      options(properties),
      str("content", content),
      str("fg", color),
      ..attributes
    ],
    [],
  )
}

fn click(message) {
  event.on("mousedown", decode.success(message))
}

pub fn screen(model: a.Model, directory) {
  box(
    [
      n.s("width", "100%"),
      n.s("height", "100%"),
      n.s("backgroundColor", h.bg),
      n.n("paddingX", 2),
    ],
    [],
    [
      box(
        [
          n.n("height", 3),
          n.n("flexShrink", 0),
          n.s("flexDirection", "row"),
          n.s("alignItems", "center"),
          n.s("justifyContent", "space-between"),
        ],
        [],
        [
          text(
            "eyg / "
              <> case model.overlay {
              True -> "overlay"
              False -> "repl"
            },
            h.accent,
            [],
            [],
          ),
          text(
            directory
              <> "  ·  "
              <> case model.overlay {
              True -> model.model_name
              False -> int.to_string(list.length(model.packages)) <> " packages"
            },
            h.muted,
            [],
            [],
          ),
        ],
      ),
      keyed.element(
        "scrollbox",
        [
          options([
            n.s("id", "history"),
            n.n("flexGrow", 1),
            n.n("minHeight", 0),
            n.b("stickyScroll", True),
            n.s("stickyStart", "bottom"),
            #("scrollbarOptions", j.object([n.b("visible", False)])),
          ]),
        ],
        [
          #(
            "intro",
            box(
              [
                n.n("paddingTop", 3),
                n.n("paddingBottom", 3),
                n.n("paddingX", 2),
                n.n("gap", 1),
              ],
              [boolean("visible", list.is_empty(model.entries))],
              [
                text("Eat Your Greens", h.text, [], []),
                text(
                  case model.overlay {
                    True -> "An agent with tools you can inspect."
                    False -> "An expression. A useful result."
                  },
                  h.muted,
                  [],
                  [],
                ),
                text(
                  case model.overlay {
                    True -> "Ask a question or describe a task to get started."
                    False -> "Try @standard.integer.add(20, 22)"
                  },
                  h.muted,
                  [],
                  [],
                ),
              ],
            ),
          ),
          ..list.map(model.entries, fn(entry) {
            let streaming = entry.role == a.Assistant && model.busy
            #(
              int.to_string(entry.id),
              e.memo([e.ref(entry), e.ref(streaming)], fn() {
                row(entry, streaming)
              }),
            )
          })
        ],
      ),
      box(
        [
          n.s("backgroundColor", h.panel),
          n.n("paddingX", 2),
          n.n("paddingY", 1),
        ],
        [boolean("visible", model.help)],
        [text(native_view.help_text(model.overlay), h.muted, [], [])],
      ),
      structure(model),
      box(
        [
          n.s("backgroundColor", h.panel),
          n.n("paddingX", 2),
          n.n("paddingY", 1),
        ],
        [boolean("visible", !model.busy && !list.is_empty(model.choices))],
        {
          let start = int.max(0, model.choice - 5)
          model.choices
          |> list.drop(start)
          |> list.take(6)
          |> list.index_map(fn(choice, index) {
            let selected = start + index == model.choice
            text(
              case selected {
                True -> "› "
                False -> "  "
              }
                <> choice.label
                <> "  "
                <> choice.detail,
              case selected {
                True -> h.accent
                False -> h.muted
              },
              [],
              [],
            )
          })
        },
      ),
      input(model),
      box(
        [
          n.n("height", 2),
          n.n("paddingTop", 1),
          n.n("flexShrink", 0),
          n.s("flexDirection", "row"),
          n.s("justifyContent", "space-between"),
        ],
        [],
        [
          text(model.status, h.muted, [], []),
          text(
            case model.overlay {
              True -> "ctrl+o code  ·  ctrl+e effects  ·  f1 help"
              False -> "ctrl+e effects  ·  f1 help"
            },
            h.muted,
            [],
            [],
          ),
        ],
      ),
    ],
  )
}

fn input(model: a.Model) {
  box(
    [
      n.s("backgroundColor", h.panel),
      #("border", j.array(["left"], j.string)),
      n.s("borderColor", h.accent),
      n.n("paddingLeft", 2),
      n.n("paddingRight", 2),
      n.n("paddingTop", 1),
      n.n("flexShrink", 0),
    ],
    [],
    [
      text(option.unwrap(model.prompt, ""), h.orange, [], [
        boolean("visible", option.is_some(model.prompt)),
      ]),
      text(
        case a.input(model) {
          Some(input) -> input.label <> " · Enter confirm · Escape cancel"
          None -> ""
        },
        h.blue,
        [],
        [boolean("visible", option.is_some(a.input(model)))],
      ),
      e.element(
        "textarea",
        [
          options([
            n.s("id", "editor"),
            n.s("textColor", h.text),
            n.s("backgroundColor", h.panel),
            n.s("focusedBackgroundColor", h.panel),
            n.s("cursorColor", h.accent),
            n.s("wrapMode", "word"),
            #(
              "keyBindings",
              j.array(
                [
                  j.object([n.s("name", "return"), n.s("action", "submit")]),
                  j.object([
                    n.s("name", "return"),
                    n.b("shift", True),
                    n.s("action", "newline"),
                  ]),
                  j.object([
                    n.s("name", "return"),
                    n.b("meta", True),
                    n.s("action", "newline"),
                  ]),
                ],
                fn(value) { value },
              ),
            ),
          ]),
          boolean("visible", a.editor_visible(model)),
          boolean("focus", a.editor_visible(model)),
          number(
            "height",
            int.min(
              9,
              int.max(2, list.length(string.split(model.source, "\n")) + 1),
            ),
          ),
          str("placeholder", case model.busy, model.prompt, model.overlay {
            True, None, _ -> "You can draft while this runs…"
            _, _, True -> "Ask anything…"
            _, _, False -> "Write EYG…"
          }),
        ],
        [],
      ),
      box(
        [
          n.n("height", 1),
          n.s("flexDirection", "row"),
          n.s("justifyContent", "space-between"),
        ],
        [],
        [
          text(
            case model.overlay, model.structural {
              True, _ -> "Overlay  " <> model.model_name
              _, True -> "Structure  EYG"
              _, _ -> "Text  EYG"
            },
            h.accent,
            [],
            [],
          ),
          text(
            case model.overlay, model.structural {
              True, _ -> "enter send  ·  shift+enter newline"
              _, True -> "enter run  ·  f2 text"
              _, _ -> "enter run  ·  tab complete  ·  f2 structure"
            },
            h.muted,
            [],
            [],
          ),
        ],
      ),
    ],
  )
}

fn structure(model: a.Model) {
  let view = option.unwrap(model.structure, p.View([], "", "", [], None, None))
  box(
    [
      n.s("backgroundColor", h.panel),
      n.n("paddingX", 2),
      n.n("paddingY", 1),
      n.n("flexShrink", 0),
    ],
    [boolean("visible", model.structural && option.is_some(model.structure))],
    [
      e.element(
        "scrollbox",
        [
          options([
            n.s("id", "structure-tree"),
            #("scrollbarOptions", j.object([n.b("visible", False)])),
          ]),
          number("height", int.min(12, int.max(2, list.length(view.lines)))),
        ],
        list.index_map(view.lines, fn(line, index) {
          e.element(
            "text",
            [
              options([n.s("id", "structural-line-" <> int.to_string(index))]),
              at.property(
                "chunks",
                j.array(line, fn(chunk) {
                  j.object([
                    n.s("text", chunk.text),
                    n.s("fg", case chunk.selected {
                      True -> h.bg
                      False -> h.color(chunk.token)
                    }),
                    n.s("bg", case chunk.selected {
                      True -> h.accent
                      False -> ""
                    }),
                    n.n("attributes", case chunk.error {
                      True -> 8
                      False -> 0
                    }),
                  ])
                }),
              ),
              event.on("mousedown", {
                use column <- decode.then(decode.int)
                decode.success(case chunk_path(line, column) {
                  Some(path) -> a.StructuralAction(p.Focus(path))
                  None -> a.Noop
                })
              }),
            ],
            [],
          )
        }),
      ),
      text(
        case view.type_ {
          "" -> "n integer · s string · @ package · F1 all shortcuts"
          value -> value
        },
        h.muted,
        [],
        [],
      ),
      text(view.errors |> list.take(2) |> string.join("\n"), h.red, [], [
        boolean("visible", !list.is_empty(view.errors)),
      ]),
    ],
  )
}

fn chunk_path(line: List(p.Chunk), column) {
  let assert Ok(host) = bun.get()
  case line {
    [] -> None
    [chunk, ..rest] -> {
      let next = column - bun.string_width(host, chunk.text)
      case next < 0 {
        True -> chunk.path
        False -> chunk_path(rest, next)
      }
    }
  }
}

fn row(entry: a.Entry, streaming) {
  let id = int.to_string(entry.id)
  let tool = entry.role == a.Tool
  let assistant = entry.role == a.Assistant
  box([n.n("marginBottom", 1)], [], [
    box(
      [n.s("backgroundColor", h.panel), n.n("paddingX", 2), n.n("paddingY", 1)],
      [boolean("visible", !assistant)],
      [
        text(
          case entry.code_expanded {
            True -> "▾ "
            False -> "▸ "
          }
            <> entry.name
            <> "  "
            <> case entry.busy {
            True -> "running"
            False -> n.milliseconds(option.unwrap(entry.duration, 0.0)) <> " ms"
          }
            <> " · code",
          h.blue,
          [n.s("id", "code-" <> id)],
          [boolean("visible", tool), click(a.ToggleCode(entry.id))],
        ),
        e.element(
          "text",
          [
            options([n.s("fg", h.text)]),
            boolean("visible", !tool || entry.code_expanded),
            str(
              case entry.role {
                a.User -> "content"
                _ -> "code"
              },
              entry.source,
            ),
          ],
          [],
        ),
      ],
    ),
    box([n.n("paddingX", 2), n.n("paddingY", 1), n.n("gap", 1)], [], [
      case assistant {
        True ->
          e.element(
            "markdown",
            [
              options([
                n.s("fg", h.text),
                n.b("conceal", True),
                n.b("streaming", True),
              ]),
              str("content", entry.output),
              boolean("streaming", streaming),
            ],
            [],
          )
        False ->
          text(string.trim_end(entry.output), h.muted, [], [
            boolean(
              "visible",
              entry.output != "" && { !tool || list.is_empty(entry.results) },
            ),
          ])
      },
      box(
        [],
        [boolean("visible", !list.is_empty(entry.results))],
        list.map(entry.results, fn(result) {
          let #(value, color) = case result {
            Ok(value) -> #(value, h.accent)
            Error(value) -> #(value, h.red)
          }
          let lines = string.split(value, "\n")
          box([], [], [
            text(
              case tool && !entry.output_expanded {
                True -> lines |> list.take(8) |> string.join("\n")
                False -> value
              },
              color,
              [],
              [],
            ),
            text(
              case entry.output_expanded {
                True -> "▾ Collapse output"
                False ->
                  "▸ Show all " <> int.to_string(list.length(lines)) <> " lines"
              },
              h.muted,
              [],
              [
                boolean("visible", tool && list.length(lines) > 8),
                click(a.ToggleOutput(entry.id)),
              ],
            ),
          ])
        }),
      ),
      text("● Running…", h.muted, [], [boolean("visible", entry.busy)]),
      text(
        case entry.expanded {
          True -> "▾ "
          False -> "▸ "
        }
          <> int.to_string(list.length(entry.effects))
          <> " effects"
          <> case list.length(entry.fetches) {
          0 -> ""
          count -> " · " <> int.to_string(count) <> " hub requests"
        }
          <> case entry.duration {
          None -> ""
          Some(duration) -> "  " <> n.milliseconds(duration) <> " ms"
        },
        h.muted,
        [n.s("id", "effects-" <> id)],
        [
          boolean("visible", entry.effects != [] || entry.fetches != []),
          click(a.ToggleEffects(entry.id)),
        ],
      ),
      box(
        [n.s("id", "details-" <> id), n.n("gap", 1)],
        [boolean("visible", entry.expanded)],
        case entry.expanded {
          False -> []
          True ->
            list.append(
              list.map(entry.fetches, fn(url) {
                text("↓ " <> url, h.blue, [], [])
              }),
              list.map(entry.effects, fn(effect) {
                box([n.n("paddingLeft", 2)], [], [
                  text(
                    effect.label <> "(" <> effect.input <> ")",
                    h.orange,
                    [],
                    [],
                  ),
                  text(
                    "↳ "
                      <> case effect.decision {
                      None -> ""
                      Some(decision) -> decision <> " · "
                    }
                      <> effect.output,
                    h.muted,
                    [],
                    [],
                  ),
                ])
              }),
            )
        },
      ),
    ]),
  ])
}
