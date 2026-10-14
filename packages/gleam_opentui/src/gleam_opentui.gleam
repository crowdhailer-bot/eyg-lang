//// Direct bindings to @opentui/core 0.5.14. Objects retain native identity,
//// mutation and lifetime. Options are the native API's JSON-compatible fields.
//// Renderer policy, event dispatch and component ownership belong to callers.

import gleam/javascript/promise.{type Promise}

pub type Renderer

pub type Node(kind)

pub type Base

pub type Box

pub type Text

pub type ScrollBox

pub type Textarea

pub type Markdown

pub type SyntaxStyle

pub type StyledText

pub type KeyEvent

pub type PasteEvent

pub type MouseEvent

pub type EditBuffer

@external(javascript, "./opentui.ffi.mjs", "nodeId")
pub fn node_id(node: Node(a)) -> String

@external(javascript, "./opentui.ffi.mjs", "y")
pub fn y(node: Node(a)) -> Int

@external(javascript, "./opentui.ffi.mjs", "isDestroyed")
pub fn is_destroyed(node: Node(a)) -> Bool

pub type Chunk {
  Chunk(text: String, fg: String, bg: String, attributes: Int)
}

@external(javascript, "./opentui.ffi.mjs", "createRenderer")
pub fn create_renderer(
  options_json: String,
) -> Promise(Result(Renderer, String))

@external(javascript, "./opentui.ffi.mjs", "root")
pub fn root(renderer: Renderer) -> Node(Base)

@external(javascript, "./opentui.ffi.mjs", "destroyRenderer")
pub fn destroy_renderer(renderer: Renderer) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "requestRender")
pub fn request_render(renderer: Renderer) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onKey")
pub fn on_key(
  renderer: Renderer,
  callback: fn(KeyEvent) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "offKey")
pub fn off_key(
  renderer: Renderer,
  callback: fn(KeyEvent) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onPaste")
pub fn on_paste(
  renderer: Renderer,
  callback: fn(PasteEvent) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "offPaste")
pub fn off_paste(
  renderer: Renderer,
  callback: fn(PasteEvent) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onceFrame")
pub fn once_frame(
  renderer: Renderer,
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "offFrame")
pub fn off_frame(
  renderer: Renderer,
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onceDestroy")
pub fn once_destroy(
  renderer: Renderer,
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "keyDetails")
pub fn key_details(key: KeyEvent) -> #(String, String, Bool, Bool, Bool)

@external(javascript, "./opentui.ffi.mjs", "preventDefault")
pub fn prevent_key_default(key: KeyEvent) -> Nil

@external(javascript, "./opentui.ffi.mjs", "preventDefault")
pub fn prevent_paste_default(event: PasteEvent) -> Nil

@external(javascript, "./opentui.ffi.mjs", "pasteBytes")
pub fn paste_bytes(event: PasteEvent) -> BitArray

@external(javascript, "./opentui.ffi.mjs", "mouseX")
pub fn mouse_x(event: MouseEvent) -> Int

@external(javascript, "./opentui.ffi.mjs", "newBox")
pub fn new_box(
  renderer: Renderer,
  options_json: String,
) -> Result(Node(Box), String)

@external(javascript, "./opentui.ffi.mjs", "newText")
pub fn new_text(
  renderer: Renderer,
  options_json: String,
) -> Result(Node(Text), String)

@external(javascript, "./opentui.ffi.mjs", "newScrollBox")
pub fn new_scroll_box(
  renderer: Renderer,
  options_json: String,
) -> Result(Node(ScrollBox), String)

@external(javascript, "./opentui.ffi.mjs", "newTextarea")
pub fn new_textarea(
  renderer: Renderer,
  options_json: String,
) -> Result(Node(Textarea), String)

@external(javascript, "./opentui.ffi.mjs", "newMarkdown")
pub fn new_markdown(
  renderer: Renderer,
  options_json: String,
  style: SyntaxStyle,
) -> Result(Node(Markdown), String)

@external(javascript, "./opentui.ffi.mjs", "identity")
pub fn as_base(node: Node(a)) -> Node(Base)

@external(javascript, "./opentui.ffi.mjs", "add")
pub fn add(parent: Node(a), child: Node(b)) -> Result(Int, String)

@external(javascript, "./opentui.ffi.mjs", "addAt")
pub fn add_at(
  parent: Node(a),
  child: Node(b),
  index: Int,
) -> Result(Int, String)

@external(javascript, "./opentui.ffi.mjs", "remove")
pub fn remove(parent: Node(a), child: Node(b)) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "children")
pub fn children(parent: Node(a)) -> List(Node(Base))

@external(javascript, "./opentui.ffi.mjs", "destroyNode")
pub fn destroy_node(node: Node(a)) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setVisible")
pub fn set_visible(node: Node(a), visible: Bool) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setHeight")
pub fn set_height(node: Node(a), height: Int) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setWidth")
pub fn set_width(node: Node(a), width: Int) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "focus")
pub fn focus(node: Node(a)) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "blur")
pub fn blur(node: Node(a)) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "x")
pub fn x(node: Node(a)) -> Int

@external(javascript, "./opentui.ffi.mjs", "onMouseDown")
pub fn on_mouse_down(
  node: Node(a),
  callback: fn(MouseEvent) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "textContent")
pub fn set_text_content(node: Node(Text), text: String) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "styledContent")
pub fn set_styled_content(
  node: Node(Text),
  text: StyledText,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "newStyledText")
pub fn new_styled_text(chunks: List(Chunk)) -> Result(StyledText, String)

@external(javascript, "./opentui.ffi.mjs", "setForeground")
pub fn set_foreground(node: Node(Text), color: String) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "markdownContent")
pub fn set_markdown_content(
  node: Node(Markdown),
  text: String,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "markdownStreaming")
pub fn set_markdown_streaming(
  node: Node(Markdown),
  streaming: Bool,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "scrollBy")
pub fn scroll_by(node: Node(ScrollBox), delta: Int) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "scrollTo")
pub fn scroll_to(node: Node(ScrollBox), position: Int) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "scrollHeight")
pub fn scroll_height(node: Node(ScrollBox)) -> Int

@external(javascript, "./opentui.ffi.mjs", "stickyScroll")
pub fn set_sticky_scroll(
  node: Node(ScrollBox),
  sticky: Bool,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "reveal")
pub fn scroll_child_into_view(
  node: Node(ScrollBox),
  id: String,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "plainText")
pub fn plain_text(node: Node(Textarea)) -> String

@external(javascript, "./opentui.ffi.mjs", "cursorOffset")
pub fn cursor_offset(node: Node(Textarea)) -> Int

@external(javascript, "./opentui.ffi.mjs", "editBuffer")
pub fn edit_buffer(node: Node(Textarea)) -> EditBuffer

@external(javascript, "./opentui.ffi.mjs", "textRange")
pub fn text_range(
  buffer: EditBuffer,
  start: Int,
  end: Int,
) -> Result(String, String)

@external(javascript, "./opentui.ffi.mjs", "setText")
pub fn set_text(node: Node(Textarea), text: String) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "replaceText")
pub fn replace_text(node: Node(Textarea), text: String) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setCursor")
pub fn set_cursor(
  node: Node(Textarea),
  row: Int,
  column: Int,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "selectAll")
pub fn select_all(node: Node(Textarea)) -> Result(Bool, String)

@external(javascript, "./opentui.ffi.mjs", "onSubmit")
pub fn on_submit(
  node: Node(Textarea),
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onContentChange")
pub fn on_content_change(
  node: Node(Textarea),
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "onCursorChange")
pub fn on_cursor_change(
  node: Node(Textarea),
  callback: fn() -> Nil,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setPlaceholder")
pub fn set_placeholder(
  node: Node(Textarea),
  text: String,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "setSyntaxStyle")
pub fn set_syntax_style(
  node: Node(Textarea),
  style: SyntaxStyle,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "clearHighlights")
pub fn clear_highlights(node: Node(Textarea)) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "addHighlight")
pub fn add_highlight(
  node: Node(Textarea),
  start: Int,
  end: Int,
  style: Int,
) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "newSyntaxStyle")
pub fn new_syntax_style(styles_json: String) -> Result(SyntaxStyle, String)

@external(javascript, "./opentui.ffi.mjs", "styleId")
pub fn style_id(
  style: SyntaxStyle,
  name: String,
) -> Result(Result(Int, Nil), String)

@external(javascript, "./opentui.ffi.mjs", "destroyStyle")
pub fn destroy_style(style: SyntaxStyle) -> Result(Nil, String)

@external(javascript, "./opentui.ffi.mjs", "copyOSC52")
pub fn copy_osc52(renderer: Renderer, text: String) -> Result(Bool, String)
