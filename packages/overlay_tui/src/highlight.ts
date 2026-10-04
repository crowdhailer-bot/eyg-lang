import { SyntaxStyle, type TextareaRenderable } from "@opentui/core";

export const colors = { bg: "#141414", panel: "#1e1e1e", text: "#eeeeee", muted: "#808080", accent: "#a9c9a0", blue: "#9bb5d6", orange: "#e5c07b", red: "#e06c75", purple: "#c792ea" };
export const tokenPattern = /\/\/[^\n]*|"(?:\\[\s\S]|[^"\\])*"?|@[a-zA-Z0-9_:.-]+|#[a-zA-Z0-9]+|![a-z_][a-z0-9_]*|\b(?:let|import|perform|handle|match)\b|\b[A-Z][a-zA-Z0-9_]*\b|-?\b\d+\b/g;
export function tokens(source: string) {
  return [...source.matchAll(new RegExp(tokenPattern))].map(match => {
    const value = match[0];
    const kind = value.startsWith("//") ? "comment" : value.startsWith('"') ? "string" : /^[@#]/.test(value) ? "reference" : value.startsWith("!") ? "builtin" : /^-?\d/.test(value) ? "number" : /^[A-Z]/.test(value) ? "tag" : "keyword";
    return { start: match.index, end: match.index + value.length, kind, value };
  });
}
export function syntaxStyle() {
  return SyntaxStyle.fromStyles({
    comment: { fg: colors.muted, italic: true }, string: { fg: colors.accent },
    reference: { fg: colors.blue }, builtin: { fg: colors.blue }, number: { fg: colors.orange },
    tag: { fg: colors.orange }, keyword: { fg: colors.purple },
  });
}

export function codeChunks(source: string) {
  const color: Record<string, string> = { comment: colors.muted, string: colors.accent, reference: colors.blue, builtin: colors.blue, number: colors.orange, tag: colors.orange, keyword: colors.purple };
  const chunks = [];
  let previous = 0;
  for (const token of tokens(source)) {
    if (token.start > previous) chunks.push({ color: colors.text, text: source.slice(previous, token.start) });
    chunks.push({ color: color[token.kind], text: token.value });
    previous = token.end;
  }
  if (previous < source.length) chunks.push({ color: colors.text, text: source.slice(previous) });
  return chunks;
}
export function highlight(editor: TextareaRenderable, style: SyntaxStyle) {
  editor.clearAllHighlights();
  const source = editor.plainText;
  let previous = 0;
  let offset = 0;
  for (const token of tokens(source)) {
    // Native ranges use Unicode character offsets, not UTF-16 indices.
    offset += [...source.slice(previous, token.start)].length;
    const end = offset + [...token.value].length;
    editor.addHighlightByCharRange({ start: offset, end, styleId: style.getStyleId(token.kind)! });
    previous = token.end;
    offset = end;
  }
}
