import {
  createCliRenderer, BoxRenderable, TextRenderable, ScrollBoxRenderable,
  TextareaRenderable, MarkdownRenderable, SyntaxStyle, StyledText, RGBA,
} from "@opentui/core";
import { Result$Ok, Result$Error, toList, toBitArray } from "./gleam.mjs";

const call = fn => (...args) => {
  try { return Result$Ok(fn(...args)); }
  catch (error) { return Result$Error(String(error)); }
};
const set = key => call((object, value) => { object[key] = value; });
export async function createRenderer(options) {
  try { return Result$Ok(await createCliRenderer(JSON.parse(options))); }
  catch (error) { return Result$Error(String(error)); }
}
export const root = renderer => renderer.root;
export const nodeId = node => node.id;
export const destroyRenderer = call(renderer => renderer.destroy());
export const requestRender = call(renderer => renderer.requestRender());
export const onKey = call((renderer, callback) => { renderer.keyInput.on("keypress", callback); });
export const offKey = call((renderer, callback) => { renderer.keyInput.off("keypress", callback); });
export const onPaste = call((renderer, callback) => { renderer.keyInput.on("paste", callback); });
export const offPaste = call((renderer, callback) => { renderer.keyInput.off("paste", callback); });
export const onceFrame = call((renderer, callback) => { renderer.once("frame", callback); });
export const offFrame = call((renderer, callback) => { renderer.off("frame", callback); });
export const onceDestroy = call((renderer, callback) => { renderer.once("destroy", callback); });
export const keyDetails = key => [key.name, key.sequence, key.ctrl, key.shift, key.meta];
export const preventDefault = event => { event.preventDefault(); };
export const pasteBytes = event => toBitArray([event.bytes]);
export const mouseX = event => event.x;
export const newBox = call((renderer, options) => new BoxRenderable(renderer, JSON.parse(options)));
export const newText = call((renderer, options) => new TextRenderable(renderer, JSON.parse(options)));
export const newScrollBox = call((renderer, options) => new ScrollBoxRenderable(renderer, JSON.parse(options)));
export const newTextarea = call((renderer, options) => new TextareaRenderable(renderer, JSON.parse(options)));
export const newMarkdown = call((renderer, options, syntaxStyle) => new MarkdownRenderable(renderer, { ...JSON.parse(options), syntaxStyle }));
export const identity = node => node;
export const add = call((parent, child) => parent.add(child));
export const addAt = call((parent, child, index) => parent.add(child, index));
export const remove = call((parent, child) => { parent.remove(child); });
export const children = node => toList(node.getChildren());
export const destroyNode = call(node => node.destroyRecursively());
export const setVisible = set("visible");
export const setHeight = set("height");
export const setWidth = set("width");
export const focus = call(node => node.focus());
export const blur = call(node => node.blur());
export const x = node => node.x;
export const y = node => node.y;
export const isDestroyed = node => node.isDestroyed;
export const onMouseDown = set("onMouseDown");
export const textContent = set("content");
export const styledContent = set("content");
export const setForeground = set("fg");
export const newStyledText = call(chunks => new StyledText([...chunks].map(chunk => ({
  __isChunk: true, text: chunk.text, fg: RGBA.fromHex(chunk.fg),
  bg: chunk.bg ? RGBA.fromHex(chunk.bg) : undefined, attributes: chunk.attributes,
}))));
export const markdownContent = set("content");
export const markdownStreaming = set("streaming");
export const scrollBy = call((node, delta) => node.scrollBy(delta));
export const scrollTo = call((node, position) => node.scrollTo(position));
export const scrollHeight = node => node.scrollHeight;
export const stickyScroll = set("stickyScroll");
export const reveal = call((node, id) => node.scrollChildIntoView(id));
export const plainText = node => node.plainText;
export const cursorOffset = node => node.cursorOffset;
export const editBuffer = node => node.editBuffer;
export const textRange = call((buffer, start, end) => buffer.getTextRange(start, end));
export const setText = call((node, text) => node.setText(text));
export const replaceText = call((node, text) => node.replaceText(text));
export const setCursor = call((node, row, column) => node.setCursor(row, column));
export const selectAll = call(node => node.selectAll());
export const onSubmit = set("onSubmit");
export const onContentChange = set("onContentChange");
export const onCursorChange = set("onCursorChange");
export const setPlaceholder = set("placeholder");
export const setSyntaxStyle = set("syntaxStyle");
export const clearHighlights = call(node => node.clearAllHighlights());
export const addHighlight = call((node, start, end, styleId) => node.addHighlightByCharRange({ start, end, styleId }));
export const newSyntaxStyle = call(styles => SyntaxStyle.fromStyles(JSON.parse(styles)));
export const styleId = call((style, name) => {
  const id = style.getStyleId(name);
  return id == null ? Result$Error(undefined) : Result$Ok(id);
});
export const destroyStyle = call(style => style.destroy());
export const copyOSC52 = call((renderer, text) => renderer.copyToClipboardOSC52(text));
