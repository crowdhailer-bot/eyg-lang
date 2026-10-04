import core/native as n
import core/native_view
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam_opentui as o
import terminal/app as a
import terminal/cell
import terminal_lustre/adapter
import terminal_lustre/render
import terminal_lustre/view

pub fn mount(renderer, initial: a.Model, dispatch, directory) {
  let style = n.style()
  let current = cell.new(None)
  let adapter =
    adapter.new(renderer, style, fn(path, name, data) {
      case cell.read(current) {
        Some(rendered) -> render.event(rendered, path, name, data)
        None -> Nil
      }
    })
  let rendered =
    render.start(
      initial,
      fn(model) { view.screen(model, directory) },
      adapter.receive(adapter, _),
      dispatch,
    )
  cell.write(current, Some(rendered))
  let assert Ok(adapter.Textarea(editor)) = adapter.find(adapter, "editor")
  let assert Ok(adapter.Scroll(history)) = adapter.find(adapter, "history")
  let assert Ok(adapter.Scroll(tree)) = adapter.find(adapter, "structure-tree")
  let pending_frame = cell.new(None)
  let previous = cell.new(None)
  let update = fn(model: a.Model) {
    render.update(rendered, model)
    case
      model.structural && cell.read(previous) != model.structure,
      model.structure
    {
      True, Some(view) -> {
        case cell.read(pending_frame) {
          Some(callback) -> o.off_frame(renderer, callback) |> n.must
          None -> Nil
        }
        let index =
          list.index_fold(view.lines, -1, fn(found, line, index) {
            case found == -1 && list.any(line, fn(chunk) { chunk.selected }) {
              True -> index
              False -> found
            }
          })
        let callback = fn() {
          cell.write(pending_frame, None)
          o.scroll_child_into_view(
            tree,
            "structural-line-" <> int.to_string(index),
          )
          |> n.must
        }
        cell.write(pending_frame, Some(callback))
        o.once_frame(renderer, callback) |> n.must
        o.request_render(renderer) |> n.must
      }
      _, _ -> Nil
    }
    cell.write(previous, model.structure)
  }
  let dispose = fn() {
    cell.write(current, None)
    case cell.read(pending_frame) {
      Some(callback) -> o.off_frame(renderer, callback) |> n.must
      None -> Nil
    }
    adapter.dispose(adapter)
    o.destroy_style(style) |> n.must
  }
  native_view.Mounted(
    native_view.Screen(
      renderer,
      editor,
      history,
      style,
      fn(_) { Nil },
      fn(_) { panic as "Rows are owned by Lustre" },
      fn(_) { Nil },
      dispose,
    ),
    update,
    dispose,
  )
}
