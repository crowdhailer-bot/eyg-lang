//// The direct core implementation retains widgets and explicitly updates their
//// properties. The signal implementation can reuse widget construction while
//// choosing its own dependency tracking and ownership.

import core/native as n
import gleam/dict
import gleam/int
import gleam/json as j
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam_opentui as o
import plinthx/bun
import terminal/app as a
import terminal/cell
import terminal/highlight as h
import terminal/protocol as p

pub type Row {
  Row(node: o.Node(o.Box), update: fn(a.Entry, Bool) -> Nil)
}

pub type Screen {
  Screen(
    renderer: o.Renderer,
    editor: o.Node(o.Textarea),
    history: o.Node(o.ScrollBox),
    style: o.SyntaxStyle,
    frame: fn(a.Model) -> Nil,
    create_row: fn(a.Entry) -> Row,
    empty: fn(Bool) -> Nil,
    dispose: fn() -> Nil,
  )
}

pub type Mounted {
  Mounted(screen: Screen, update: fn(a.Model) -> Nil, dispose: fn() -> Nil)
}

pub fn mount(renderer, initial, dispatch, directory) {
  let screen = create(renderer, initial, dispatch, directory)
  let rows = cell.new(dict.new())
  let update = fn(model: a.Model) {
    screen.frame(model)
    screen.empty(list.is_empty(model.entries))
    list.each(model.entries, fn(entry) {
      let row = case dict.get(cell.read(rows), entry.id) {
        Ok(row) -> row
        Error(_) -> {
          let row = screen.create_row(entry)
          cell.write(rows, dict.insert(cell.read(rows), entry.id, row))
          row
        }
      }
      row.update(entry, model.busy)
    })
  }
  update(initial)
  Mounted(screen, update, screen.dispose)
}

pub fn create(renderer, initial: a.Model, dispatch, directory) {
  let style = n.style()
  let root =
    n.box(renderer, o.root(renderer), [
      n.s("width", "100%"),
      n.s("height", "100%"),
      n.s("backgroundColor", h.bg),
      n.n("paddingX", 2),
    ])
  let header =
    n.box(renderer, root, [
      n.n("height", 3),
      n.n("flexShrink", 0),
      n.s("flexDirection", "row"),
      n.s("alignItems", "center"),
      n.s("justifyContent", "space-between"),
    ])
  let heading =
    n.text(
      renderer,
      header,
      "eyg / "
        <> case initial.overlay {
        True -> "overlay"
        False -> "repl"
      },
      h.accent,
      [],
    )
  let _ = heading
  let context = n.text(renderer, header, "", h.muted, [])
  let history =
    n.scroll(renderer, root, [
      n.n("flexGrow", 1),
      n.n("minHeight", 0),
      n.b("stickyScroll", True),
      n.s("stickyStart", "bottom"),
    ])
  let intro =
    n.box(renderer, history, [
      n.n("paddingTop", 3),
      n.n("paddingBottom", 3),
      n.n("paddingX", 2),
      n.n("gap", 1),
    ])
  n.text(renderer, intro, "Eat Your Greens", h.text, [])
  n.text(
    renderer,
    intro,
    case initial.overlay {
      True -> "An agent with tools you can inspect."
      False -> "An expression. A useful result."
    },
    h.muted,
    [],
  )
  n.text(
    renderer,
    intro,
    case initial.overlay {
      True -> "Ask a question or describe a task to get started."
      False -> "Try @standard.integer.add(20, 22)"
    },
    h.muted,
    [],
  )
  let help =
    n.box(renderer, root, [
      n.s("backgroundColor", h.panel),
      n.n("paddingX", 2),
      n.n("paddingY", 1),
    ])
  n.text(renderer, help, help_text(initial.overlay), h.muted, [])
  let structural =
    n.box(renderer, root, [
      n.s("backgroundColor", h.panel),
      n.n("paddingX", 2),
      n.n("paddingY", 1),
      n.n("flexShrink", 0),
    ])
  let tree = n.scroll(renderer, structural, [n.n("height", 2)])
  let type_ = n.text(renderer, structural, "", h.muted, [])
  let errors = n.text(renderer, structural, "", h.red, [])
  let choices =
    n.box(renderer, root, [
      n.s("backgroundColor", h.panel),
      n.n("paddingX", 2),
      n.n("paddingY", 1),
    ])
  let input_panel =
    n.box(renderer, root, [
      n.s("backgroundColor", h.panel),
      #("border", j.array(["left"], j.string)),
      n.s("borderColor", h.accent),
      n.n("paddingLeft", 2),
      n.n("paddingRight", 2),
      n.n("paddingTop", 1),
      n.n("flexShrink", 0),
    ])
  let prompt = n.text(renderer, input_panel, "", h.orange, [])
  let picker = n.text(renderer, input_panel, "", h.blue, [])
  let editor =
    o.new_textarea(
      renderer,
      n.props([
        n.n("height", 2),
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
    )
    |> n.must
  o.set_syntax_style(editor, style) |> n.must
  o.add(input_panel, editor) |> n.must
  let input_footer =
    n.box(renderer, input_panel, [
      n.n("height", 1),
      n.s("flexDirection", "row"),
      n.s("justifyContent", "space-between"),
    ])
  let mode = n.text(renderer, input_footer, "", h.accent, [])
  let shortcuts = n.text(renderer, input_footer, "", h.muted, [])
  let footer =
    n.box(renderer, root, [
      n.n("height", 2),
      n.n("paddingTop", 1),
      n.n("flexShrink", 0),
      n.s("flexDirection", "row"),
      n.s("justifyContent", "space-between"),
    ])
  let status = n.text(renderer, footer, "", h.muted, [])
  n.text(
    renderer,
    footer,
    case initial.overlay {
      True -> "ctrl+o code  ·  ctrl+e effects  ·  f1 help"
      False -> "ctrl+e effects  ·  f1 help"
    },
    h.muted,
    [],
  )
  let previous = cell.new(None)
  let pending_frame = cell.new(None)
  let assert Ok(host) = bun.get()
  let frame = fn(model: a.Model) {
    let old = cell.read(previous)
    let first = old == None
    let old_model = option.unwrap(old, initial)
    if_changed(
      first
        || old_model.packages != model.packages
        || old_model.model_name != model.model_name,
      fn() {
        o.set_text_content(
          context,
          directory
            <> "  ·  "
            <> case model.overlay {
            True -> model.model_name
            False -> int.to_string(list.length(model.packages)) <> " packages"
          },
        )
        |> n.must
      },
    )
    if_changed(first || old_model.status != model.status, fn() {
      o.set_text_content(status, model.status) |> n.must
    })
    if_changed(first || old_model.help != model.help, fn() {
      o.set_visible(help, model.help) |> n.must
    })
    if_changed(
      first
        || old_model.structural != model.structural
        || old_model.structure != model.structure,
      fn() {
        o.set_visible(
          structural,
          model.structural && option.is_some(model.structure),
        )
        |> n.must
        case model.structure {
          None -> Nil
          Some(view) -> {
            n.clear(tree)
            o.set_height(tree, int.min(12, int.max(2, list.length(view.lines))))
            |> n.must
            index_each(view.lines, fn(line, index) {
              let node =
                n.text(renderer, tree, "", h.text, [
                  n.s("id", "structural-line-" <> int.to_string(index)),
                ])
              n.styled(
                node,
                list.map(line, fn(chunk) {
                  o.Chunk(
                    chunk.text,
                    case chunk.selected {
                      True -> h.bg
                      False -> h.color(chunk.token)
                    },
                    case chunk.selected {
                      True -> h.accent
                      False -> ""
                    },
                    case chunk.error {
                      True -> 8
                      False -> 0
                    },
                  )
                }),
              )
              o.on_mouse_down(node, fn(event) {
                case chunk_path(line, o.mouse_x(event) - o.x(node), host) {
                  Some(path) -> dispatch(a.StructuralAction(p.Focus(path)))
                  None -> Nil
                }
              })
              |> n.must
            })
            o.set_text_content(type_, case view.type_ {
              "" -> "n integer · s string · @ package · F1 all shortcuts"
              value -> value
            })
            |> n.must
            o.set_text_content(
              errors,
              view.errors |> list.take(2) |> string.join("\n"),
            )
            |> n.must
            o.set_visible(errors, !list.is_empty(view.errors)) |> n.must
            case cell.read(pending_frame) {
              Some(callback) -> o.off_frame(renderer, callback) |> n.must
              None -> Nil
            }
            let selected =
              list.index_fold(view.lines, -1, fn(found, line, index) {
                case
                  found == -1 && list.any(line, fn(chunk) { chunk.selected })
                {
                  True -> index
                  False -> found
                }
              })
            let reveal = fn() {
              o.scroll_child_into_view(
                tree,
                "structural-line-" <> int.to_string(selected),
              )
              |> n.must
            }
            cell.write(pending_frame, Some(reveal))
            o.once_frame(renderer, reveal) |> n.must
            o.request_render(renderer) |> n.must
          }
        }
      },
    )
    if_changed(
      first
        || old_model.choices != model.choices
        || old_model.choice != model.choice
        || old_model.busy != model.busy,
      fn() {
        n.clear(choices)
        o.set_visible(choices, !model.busy && !list.is_empty(model.choices))
        |> n.must
        let start = int.max(0, model.choice - 5)
        index_each(
          model.choices |> list.drop(start) |> list.take(6),
          fn(choice, index) {
            let selected = start + index == model.choice
            n.text(
              renderer,
              choices,
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
            )
            Nil
          },
        )
      },
    )
    if_changed(first || old_model.prompt != model.prompt, fn() {
      o.set_visible(prompt, option.is_some(model.prompt)) |> n.must
      o.set_text_content(prompt, option.unwrap(model.prompt, "")) |> n.must
    })
    if_changed(first || a.input(old_model) != a.input(model), fn() {
      o.set_visible(picker, option.is_some(a.input(model))) |> n.must
      o.set_text_content(picker, case a.input(model) {
        Some(input) -> input.label <> " · Enter confirm · Escape cancel"
        None -> ""
      })
      |> n.must
    })
    if_changed(
      first || a.editor_visible(old_model) != a.editor_visible(model),
      fn() {
        o.set_visible(editor, a.editor_visible(model)) |> n.must
        case a.editor_visible(model) {
          True -> o.focus(editor) |> n.must
          False -> o.blur(editor) |> n.must
        }
      },
    )
    if_changed(first || old_model.source != model.source, fn() {
      o.set_height(
        editor,
        int.min(
          9,
          int.max(2, list.length(string.split(model.source, "\n")) + 1),
        ),
      )
      |> n.must
    })
    if_changed(
      first || old_model.busy != model.busy || old_model.prompt != model.prompt,
      fn() {
        o.set_placeholder(editor, case model.busy, model.prompt, model.overlay {
          True, None, _ -> "You can draft while this runs…"
          _, _, True -> "Ask anything…"
          _, _, False -> "Write EYG…"
        })
        |> n.must
      },
    )
    if_changed(
      first
        || old_model.structural != model.structural
        || old_model.model_name != model.model_name,
      fn() {
        o.set_text_content(mode, case model.overlay, model.structural {
          True, _ -> "Overlay  " <> model.model_name
          _, True -> "Structure  EYG"
          _, _ -> "Text  EYG"
        })
        |> n.must
        o.set_text_content(shortcuts, case model.overlay, model.structural {
          True, _ -> "enter send  ·  shift+enter newline"
          _, True -> "enter run  ·  f2 text"
          _, _ -> "enter run  ·  tab complete  ·  f2 structure"
        })
        |> n.must
      },
    )
    cell.write(previous, Some(model))
  }
  Screen(
    renderer,
    editor,
    history,
    style,
    frame,
    fn(entry) { create_row(renderer, history, entry, style, dispatch) },
    fn(empty) { o.set_visible(intro, empty) |> n.must },
    fn() {
      case cell.read(pending_frame) {
        Some(callback) -> o.off_frame(renderer, callback) |> n.must
        None -> Nil
      }
      o.destroy_node(root) |> n.must
      o.destroy_style(style) |> n.must
    },
  )
}

fn create_row(renderer, history, initial: a.Entry, style, dispatch) {
  let root = n.box(renderer, history, [n.n("marginBottom", 1)])
  let id = int.to_string(initial.id)
  let source_update = case initial.role {
    a.Assistant -> fn(_: a.Entry) { Nil }
    _ -> {
      let panel =
        n.box(renderer, root, [
          n.s("backgroundColor", h.panel),
          n.n("paddingX", 2),
          n.n("paddingY", 1),
        ])
      let title = case initial.role {
        a.Tool -> {
          let node =
            n.text(renderer, panel, "", h.blue, [n.s("id", "code-" <> id)])
          o.on_mouse_down(node, fn(_) { dispatch(a.ToggleCode(initial.id)) })
          |> n.must
          Some(node)
        }
        _ -> None
      }
      let code = n.text(renderer, panel, initial.source, h.text, [])
      case initial.role {
        a.User -> Nil
        _ -> n.code(code, initial.source)
      }
      fn(entry: a.Entry) {
        case title {
          Some(title) -> {
            o.set_text_content(
              title,
              case entry.code_expanded {
                True -> "▾ "
                False -> "▸ "
              }
                <> entry.name
                <> "  "
                <> case entry.busy {
                True -> "running"
                False ->
                  n.milliseconds(option.unwrap(entry.duration, 0.0)) <> " ms"
              }
                <> " · code",
            )
            |> n.must
            o.set_visible(code, entry.code_expanded) |> n.must
          }
          None -> Nil
        }
      }
    }
  }
  let body =
    n.box(renderer, root, [
      n.n("paddingX", 2),
      n.n("paddingY", 1),
      n.n("gap", 1),
    ])
  let output_update = case initial.role {
    a.Assistant -> {
      let markdown =
        o.new_markdown(
          renderer,
          n.props([
            n.s("content", initial.output),
            n.s("fg", h.text),
            n.b("conceal", True),
            n.b("streaming", True),
          ]),
          style,
        )
        |> n.must
      o.add(body, markdown) |> n.must
      fn(entry: a.Entry, busy) {
        o.set_markdown_content(markdown, entry.output) |> n.must
        o.set_markdown_streaming(markdown, busy) |> n.must
      }
    }
    _ -> {
      let output = n.text(renderer, body, "", h.muted, [])
      fn(entry: a.Entry, _) {
        o.set_text_content(output, string.trim_end(entry.output)) |> n.must
        o.set_visible(
          output,
          entry.output != ""
            && { entry.role != a.Tool || list.is_empty(entry.results) },
        )
        |> n.must
      }
    }
  }
  let results = n.box(renderer, body, [])
  let running = n.text(renderer, body, "● Running…", h.muted, [])
  let effects =
    n.text(renderer, body, "", h.muted, [n.s("id", "effects-" <> id)])
  o.on_mouse_down(effects, fn(_) { dispatch(a.ToggleEffects(initial.id)) })
  |> n.must
  let details =
    n.box(renderer, body, [n.s("id", "details-" <> id), n.n("gap", 1)])
  let previous = cell.new(None)
  let previous_busy = cell.new(False)
  let update = fn(entry: a.Entry, busy) {
    let old = cell.read(previous)
    let first = old == None
    let before = option.unwrap(old, initial)
    if_changed(
      first
        || before.code_expanded != entry.code_expanded
        || before.busy != entry.busy
        || before.duration != entry.duration,
      fn() { source_update(entry) },
    )
    if_changed(
      first
        || before.output != entry.output
        || before.results != entry.results
        || cell.read(previous_busy) != busy,
      fn() { output_update(entry, busy) },
    )
    if_changed(
      first
        || before.results != entry.results
        || before.output_expanded != entry.output_expanded,
      fn() {
        n.clear(results)
        o.set_visible(results, !list.is_empty(entry.results)) |> n.must
        list.each(entry.results, fn(result) {
          let #(text, color) = case result {
            Ok(text) -> #(text, h.accent)
            Error(text) -> #(text, h.red)
          }
          let lines = string.split(text, "\n")
          let displayed = case entry.role == a.Tool && !entry.output_expanded {
            True -> lines |> list.take(8) |> string.join("\n")
            False -> text
          }
          n.text(renderer, results, displayed, color, [])
          case entry.role == a.Tool && list.length(lines) > 8 {
            True -> {
              let button =
                n.text(
                  renderer,
                  results,
                  case entry.output_expanded {
                    True -> "▾ Collapse output"
                    False ->
                      "▸ Show all "
                      <> int.to_string(list.length(lines))
                      <> " lines"
                  },
                  h.muted,
                  [],
                )
              o.on_mouse_down(button, fn(_) {
                dispatch(a.ToggleOutput(entry.id))
              })
              |> n.must
            }
            False -> Nil
          }
        })
      },
    )
    if_changed(first || before.busy != entry.busy, fn() {
      o.set_visible(running, entry.busy) |> n.must
    })
    if_changed(
      first
        || before.effects != entry.effects
        || before.fetches != entry.fetches
        || before.duration != entry.duration
        || before.expanded != entry.expanded,
      fn() {
        let count = list.length(entry.effects)
        let fetches = list.length(entry.fetches)
        o.set_visible(effects, count > 0 || fetches > 0) |> n.must
        o.set_text_content(
          effects,
          case entry.expanded {
            True -> "▾ "
            False -> "▸ "
          }
            <> int.to_string(count)
            <> " effects"
            <> case fetches {
            0 -> ""
            _ -> " · " <> int.to_string(fetches) <> " hub requests"
          }
            <> case entry.duration {
            None -> ""
            Some(duration) -> "  " <> n.milliseconds(duration) <> " ms"
          },
        )
        |> n.must
        o.set_visible(details, entry.expanded) |> n.must
        n.clear(details)
        case entry.expanded {
          False -> Nil
          True -> {
            list.each(entry.fetches, fn(url) {
              n.text(renderer, details, "↓ " <> url, h.blue, [])
              Nil
            })
            list.each(entry.effects, fn(effect) {
              let group = n.box(renderer, details, [n.n("paddingLeft", 2)])
              n.text(
                renderer,
                group,
                effect.label <> "(" <> effect.input <> ")",
                h.orange,
                [],
              )
              n.text(
                renderer,
                group,
                "↳ "
                  <> case effect.decision {
                  None -> ""
                  Some(decision) -> decision <> " · "
                }
                  <> effect.output,
                h.muted,
                [],
              )
              Nil
            })
          }
        }
      },
    )
    cell.write(previous, Some(entry))
    cell.write(previous_busy, busy)
  }
  Row(root, update)
}

fn if_changed(condition, run) {
  case condition {
    True -> run()
    False -> Nil
  }
}

fn index_each(items, run) {
  list.index_fold(items, Nil, fn(_, item, index) { run(item, index) })
}

fn chunk_path(line: List(p.Chunk), column, host) {
  case line {
    [] -> None
    [chunk, ..rest] -> {
      let next = column - bun.string_width(host, chunk.text)
      case next < 0 {
        True -> chunk.path
        False -> chunk_path(rest, next, host)
      }
    }
  }
}

pub fn help_text(overlay) {
  "Enter run · Shift+Enter newline · Tab complete · Ctrl+E effects · Ctrl+O code · PgUp/PgDn scroll\n/scope bindings · /type expression · /help · /exit · Ctrl+C quit · F1 close help"
  <> case overlay {
    True -> ""
    False ->
      "\nF2 text/structure · arrows navigate · Space vacant · a select parent · i edit · d delete · z/Z undo/redo\nn integer · s string · b binary · v variable · f function · c/C/w call · e/E let · l/L list · r/R record\ng field · o overwrite · t tag · m match · p/h effects · j builtin · @/# reference · q/Q file · x spread\ny/Y copy/paste · k fold · </> insert before/after · Enter evaluate · Escape dismiss / text"
  }
}
