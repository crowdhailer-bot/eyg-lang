//// Apply Lustre 5.7.1's native Mount/Reconcile messages to OpenTUI. The real
//// Lustre modules own diffing, memo caching, keyed matching and event decoding.
//// Metadata keeps virtual fragments/maps distinct from native widget children.

import core/native as n
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as d
import gleam/json as j
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam_opentui as o
import lustre/internals/mutable_map
import lustre/runtime/transport
import lustre/vdom/patch as p
import lustre/vdom/path
import lustre/vdom/vattr as a
import lustre/vdom/vnode as v
import terminal/cell.{type Cell}

pub type Widget {
  Base(o.Node(o.Base))
  Box(o.Node(o.Box))
  Text(o.Node(o.Text))
  Scroll(o.Node(o.ScrollBox))
  Textarea(o.Node(o.Textarea))
  Markdown(o.Node(o.Markdown))
}

type Meta {
  Meta(
    uid: Int,
    key: String,
    subtree: Bool,
    widget: Option(Widget),
    children: Cell(List(Meta)),
    parent: Option(Meta),
  )
}

pub opaque type Adapter(message) {
  Adapter(
    renderer: o.Renderer,
    style: o.SyntaxStyle,
    root: Meta,
    next: Cell(Int),
    event: fn(String, String, Dynamic) -> Nil,
  )
}

pub fn new(renderer, style, event) {
  Adapter(
    renderer,
    style,
    Meta(0, "", False, Some(Base(o.root(renderer))), cell.new([]), None),
    cell.new(1),
    event,
  )
}

pub fn node(widget: Widget) {
  case widget {
    Base(node) -> node
    Box(node) -> o.as_base(node)
    Text(node) -> o.as_base(node)
    Scroll(node) -> o.as_base(node)
    Textarea(node) -> o.as_base(node)
    Markdown(node) -> o.as_base(node)
  }
}

pub fn receive(
  adapter: Adapter(message),
  message: transport.ClientMessage(message),
) {
  case message {
    transport.Mount(vdom:, memos:, ..) -> {
      list.each(cell.read(adapter.root.children), destroy)
      cell.write(adapter.root.children, [
        build(adapter, adapter.root, vdom, memos),
      ])
      sync(adapter.root)
    }
    transport.Reconcile(patch:, memos:, ..) ->
      reconcile(adapter, adapter.root, patch, memos)
    transport.Emit(..)
    | transport.Provide(..)
    | transport.Subscribe(..)
    | transport.Unsubscribe(..) -> Nil
  }
}

pub fn find(adapter: Adapter(message), id) {
  find_in(adapter.root, id)
}

fn find_in(meta: Meta, id: String) -> Result(Widget, Nil) {
  case meta.widget {
    Some(widget) if id == "" -> Ok(widget)
    Some(widget) ->
      case o.node_id(node(widget)) == id {
        True -> Ok(widget)
        False -> find_children(cell.read(meta.children), id)
      }
    None -> find_children(cell.read(meta.children), id)
  }
}

fn find_children(children: List(Meta), id: String) -> Result(Widget, Nil) {
  case children {
    [] -> Error(Nil)
    [child, ..rest] ->
      case find_in(child, id) {
        Ok(widget) -> Ok(widget)
        Error(_) -> find_children(rest, id)
      }
  }
}

pub fn dispose(adapter: Adapter(message)) {
  list.each(cell.read(adapter.root.children), destroy)
  cell.write(adapter.root.children, [])
}

fn build(
  adapter: Adapter(message),
  parent: Meta,
  vnode: v.Element(message),
  memos: v.Memos(message),
) -> Meta {
  case vnode {
    v.Memo(view:, ..) ->
      build(
        adapter,
        parent,
        mutable_map.get_or_compute(memos, view, view),
        memos,
      )
    _ -> {
      let #(widget, subtree, attributes, children) = case vnode {
        v.Element(tag:, attributes:, children:, ..) -> #(
          Some(construct(adapter, tag, attributes)),
          False,
          attributes,
          children,
        )
        v.Text(content:, ..) -> #(
          Some(Text(
            o.new_text(adapter.renderer, n.props([n.s("content", content)]))
            |> n.must,
          )),
          False,
          [],
          [],
        )
        v.Fragment(children:, ..) -> #(None, False, [], children)
        v.Map(child:, ..) -> #(None, True, [], [child])
        v.UnsafeInnerHtml(..) -> panic as "HTML has no terminal representation"
        v.Memo(..) -> panic as "Memo handled above"
      }
      let id = cell.read(adapter.next)
      cell.write(adapter.next, id + 1)
      let meta =
        Meta(id, vnode.key, subtree, widget, cell.new([]), Some(parent))
      cell.write(
        meta.children,
        list.map(children, build(adapter, meta, _, memos)),
      )
      case widget {
        Some(_) -> sync(meta)
        None -> Nil
      }
      apply_attributes(adapter, meta, attributes)
      meta
    }
  }
}

fn construct(
  adapter: Adapter(message),
  tag,
  attributes: List(a.Attribute(message)),
) {
  let options =
    attributes
    |> list.find_map(fn(attr) {
      case attr {
        a.Property(name: "options", value:, ..) -> Ok(j.to_string(value))
        _ -> Error(Nil)
      }
    })
    |> result.unwrap("{}")
  case tag {
    "box" -> Box(o.new_box(adapter.renderer, options) |> n.must)
    "text" -> Text(o.new_text(adapter.renderer, options) |> n.must)
    "scrollbox" -> Scroll(o.new_scroll_box(adapter.renderer, options) |> n.must)
    "textarea" -> {
      let editor = o.new_textarea(adapter.renderer, options) |> n.must
      o.set_syntax_style(editor, adapter.style) |> n.must
      Textarea(editor)
    }
    "markdown" ->
      Markdown(
        o.new_markdown(adapter.renderer, options, adapter.style) |> n.must,
      )
    _ -> {
      let message = "Unknown terminal element: " <> tag
      panic as message
    }
  }
}

fn decoded(value, decoder) {
  j.parse(j.to_string(value), decoder)
  |> result.replace_error("Invalid terminal attribute")
  |> n.must
}

fn apply_attribute(
  adapter: Adapter(message),
  meta: Meta,
  attribute: a.Attribute(message),
) {
  let assert Some(widget) = meta.widget
  case attribute {
    a.Property(name: "options", ..) -> Nil
    a.Property(name: "visible", value:, ..) ->
      o.set_visible(node(widget), decoded(value, d.bool)) |> n.must
    a.Property(name: "height", value:, ..) ->
      o.set_height(node(widget), decoded(value, d.int)) |> n.must
    a.Property(name: "focus", value:, ..) ->
      case decoded(value, d.bool) {
        True -> o.focus(node(widget)) |> n.must
        False -> o.blur(node(widget)) |> n.must
      }
    a.Property(name: "content", value:, ..) ->
      case widget {
        Text(text) ->
          o.set_text_content(text, decoded(value, d.string)) |> n.must
        Markdown(markdown) ->
          o.set_markdown_content(markdown, decoded(value, d.string)) |> n.must
        _ -> panic as "content requires text or markdown"
      }
    a.Property(name: "code", value:, ..) -> {
      let assert Text(text) = widget
      n.code(text, decoded(value, d.string))
    }
    a.Property(name: "chunks", value:, ..) -> {
      let assert Text(text) = widget
      let chunks =
        decoded(
          value,
          d.list({
            use text <- d.field("text", d.string)
            use fg <- d.field("fg", d.string)
            use bg <- d.field("bg", d.string)
            use attributes <- d.field("attributes", d.int)
            d.success(o.Chunk(text, fg, bg, attributes))
          }),
        )
      n.styled(text, chunks)
    }
    a.Property(name: "streaming", value:, ..) -> {
      let assert Markdown(markdown) = widget
      o.set_markdown_streaming(markdown, decoded(value, d.bool)) |> n.must
    }
    a.Property(name: "placeholder", value:, ..) -> {
      let assert Textarea(editor) = widget
      o.set_placeholder(editor, decoded(value, d.string)) |> n.must
    }
    a.Property(name: "fg", value:, ..) -> {
      let assert Text(text) = widget
      o.set_foreground(text, decoded(value, d.string)) |> n.must
    }
    a.Event(name: "mousedown", debounce: 0, throttle: 0, ..) ->
      o.on_mouse_down(node(widget), fn(event) {
        adapter.event(
          event_path(meta),
          "mousedown",
          dynamic.int(o.mouse_x(event) - o.x(node(widget))),
        )
      })
      |> n.must
    _ -> panic as "Unsupported terminal attribute"
  }
}

fn remove_attribute(meta: Meta, attribute: a.Attribute(message)) {
  let assert Some(widget) = meta.widget
  case attribute.name {
    "mousedown" -> o.on_mouse_down(node(widget), fn(_) { Nil }) |> n.must
    "visible" -> o.set_visible(node(widget), True) |> n.must
    "focus" -> o.blur(node(widget)) |> n.must
    _ -> panic as "Removing this terminal property is unsupported"
  }
}

fn apply_attributes(
  adapter: Adapter(message),
  meta: Meta,
  attributes: List(a.Attribute(message)),
) {
  // Native focus must follow visibility, regardless of Lustre's attribute sort.
  list.each(
    list.filter(attributes, fn(attribute) { attribute.name != "focus" }),
    apply_attribute(adapter, meta, _),
  )
  list.each(
    list.filter(attributes, fn(attribute) { attribute.name == "focus" }),
    apply_attribute(adapter, meta, _),
  )
}

fn event_path(meta: Meta) {
  meta |> metadata_path |> path.to_string
}

fn metadata_path(meta: Meta) {
  case meta.parent {
    None -> path.root
    Some(parent) -> {
      let prefix = metadata_path(parent)
      let prefix = case parent.subtree {
        True -> path.subtree(prefix)
        False -> prefix
      }
      let index =
        list.index_fold(cell.read(parent.children), 0, fn(found, child, index) {
          case child.uid == meta.uid {
            True -> index
            False -> found
          }
        })
      path.add(prefix, index, meta.key)
    }
  }
}

fn flatten(meta: Meta) -> List(o.Node(o.Base)) {
  case meta.widget {
    Some(widget) -> [node(widget)]
    None -> cell.read(meta.children) |> list.flat_map(flatten)
  }
}

fn anchor(meta: Meta) -> Meta {
  case meta.widget, meta.parent {
    Some(_), _ -> meta
    None, Some(parent) -> anchor(parent)
    None, None -> panic as "Missing native root"
  }
}

fn sync(meta: Meta) {
  let parent = anchor(meta)
  let assert Some(widget) = parent.widget
  let parent_node = node(widget)
  list.index_fold(
    cell.read(parent.children) |> list.flat_map(flatten),
    Nil,
    fn(_, child, index) {
      let existing = o.children(parent_node) |> list.drop(index) |> list.first
      let same =
        result.map(existing, fn(existing) {
          o.node_id(existing) == o.node_id(child)
        })
        |> result.unwrap(False)
      case same {
        True -> Nil
        False -> {
          o.add_at(parent_node, child, index) |> n.must
          Nil
        }
      }
    },
  )
}

fn destroy(meta: Meta) {
  // Destroy native descendants once; virtual fragments have no native owner.
  list.each(flatten(meta), fn(node) { o.destroy_node(node) |> n.must })
}

fn at(children, index) {
  let assert Ok(child) = children |> list.drop(index) |> list.first
  child
}

fn insert_at(items, index, additions) {
  list.append(
    list.take(items, index),
    list.append(additions, list.drop(items, index)),
  )
}

fn remove(meta: Meta, index, count) {
  let children = cell.read(meta.children)
  children |> list.drop(index) |> list.take(count) |> list.each(destroy)
  cell.write(
    meta.children,
    list.append(list.take(children, index), list.drop(children, index + count)),
  )
}

fn reconcile(
  adapter: Adapter(message),
  start: Meta,
  patch: p.Patch(message),
  memos: v.Memos(message),
) -> Nil {
  let meta =
    list.fold(patch.path, start, fn(node, index) {
      at(cell.read(node.children), index)
    })
  list.each(patch.changes, fn(change) {
    case change {
      p.ReplaceText(content:, ..) -> {
        let assert Some(Text(text)) = meta.widget
        o.set_text_content(text, content) |> n.must
      }
      p.ReplaceInnerHtml(..) -> panic as "HTML has no terminal representation"
      p.Update(added:, removed:, ..) -> {
        list.each(removed, remove_attribute(meta, _))
        apply_attributes(adapter, meta, added)
      }
      p.Move(key:, before:, ..) -> {
        let children = cell.read(meta.children)
        let assert Ok(child) =
          list.find(children, fn(child) { child.key == key })
        let rest = list.filter(children, fn(item) { item.uid != child.uid })
        cell.write(meta.children, insert_at(rest, before, [child]))
      }
      p.Remove(index:, ..) -> remove(meta, index, 1)
      p.Replace(index:, with:, ..) -> {
        remove(meta, index, 1)
        let child = build(adapter, meta, with, memos)
        cell.write(
          meta.children,
          insert_at(cell.read(meta.children), index, [child]),
        )
      }
      p.Insert(children:, before:, ..) -> {
        let children = list.map(children, build(adapter, meta, _, memos))
        cell.write(
          meta.children,
          insert_at(cell.read(meta.children), before, children),
        )
      }
    }
  })
  case patch.removed {
    0 -> Nil
    count -> remove(meta, list.length(cell.read(meta.children)) - count, count)
  }
  case
    patch.removed > 0
    || list.any(patch.changes, fn(change) {
      case change {
        p.Move(..) | p.Remove(..) | p.Replace(..) | p.Insert(..) -> True
        _ -> False
      }
    })
  {
    True -> sync(meta)
    False -> Nil
  }
  list.each(patch.children, fn(child) {
    reconcile(adapter, at(cell.read(meta.children), child.index), child, memos)
  })
}
