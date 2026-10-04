import { Element, Fragment, Text, type Element$ } from "../build/dev/javascript/lustre/lustre/vdom/vnode.mjs";
import { Attribute } from "../build/dev/javascript/lustre/lustre/vdom/vattr.mjs";
import type { StructuralChunk } from "./protocol";

// Adapt Morph's existing projection, including selection, folds, error marks,
// indentation and clickable paths. No second AST renderer to keep in sync.
export function project(elements: Iterable<Element$<unknown>>): StructuralChunk[][] {
  const lines: StructuralChunk[][] = [[]];
  const newline = () => { if (lines.at(-1)!.length) lines.push([]); };
  function visit(node: Element$<unknown>, inherited: Omit<StructuralChunk, "text">, indent: number) {
    if (node instanceof Text) {
      const parts = node.content.split("\n");
      for (let index = 0; index < parts.length; index++) {
        if (index) lines.push([]);
        if (!parts[index]) continue;
        const line = lines.at(-1)!;
        if (!line.length && indent) line.push({ text: " ".repeat(indent) });
        line.push({ ...inherited, text: parts[index]! });
      }
      return;
    }
    if (!(node instanceof Element || node instanceof Fragment)) return;
    const attributes = node instanceof Element ? Object.fromEntries([...node.attributes].filter((attr): attr is Attribute => attr instanceof Attribute).map(attr => [attr.name, attr.value])) : {};
    const style = attributes.style ?? "";
    const next = { ...inherited };
    if (attributes.class) next.token = attributes.class.replace("token ", "");
    if (style.includes("background-color")) next.selected = true;
    if (style.includes("underline")) next.error = true;
    if (attributes["data-rev"] !== undefined) next.path = attributes["data-rev"] === "" ? [] : attributes["data-rev"]!.split(",").map(Number).reverse();
    const block = node instanceof Element && node.tag === "div";
    if (block) newline();
    for (const child of node.children) visit(child, next, indent + (style.includes("padding-left") ? 2 : 0));
    if (block) newline();
  }
  for (const element of elements) visit(element, {}, 0);
  if (!lines.at(-1)!.length && lines.length > 1) lines.pop();
  return lines;
}

export function projectionText(lines: StructuralChunk[][]) {
  return lines.map(line => line.map(chunk => chunk.text).join("")).join("\n");
}
