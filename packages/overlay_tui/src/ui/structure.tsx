import { For, createEffect, onCleanup } from "solid-js";
import { useRenderer } from "@opentui/solid";
import type { ScrollBoxRenderable, TextRenderable } from "@opentui/core";
import type { StructuralView } from "../protocol";
import { colors } from "../highlight";

const tokenColors: Record<string, string> = { comment: colors.muted, string: colors.accent, number: colors.orange, "class-name": colors.orange, keyword: colors.purple, builtin: colors.blue, symbol: colors.blue, important: colors.red, char: colors.accent };
export function Structure(props: { view: StructuralView; focus: (path: number[]) => void }) {
  let scroll!: ScrollBoxRenderable;
  const renderer = useRenderer();
  createEffect(() => {
    const selected = props.view.lines.findIndex(line => line.some(chunk => chunk.selected));
    const reveal = () => scroll?.scrollChildIntoView(`structural-line-${selected}`);
    renderer.once("frame", reveal);
    onCleanup(() => renderer.removeListener("frame", reveal));
    renderer.requestRender();
  });
  return <box backgroundColor={colors.panel} paddingX={2} paddingY={1} flexShrink={0}>
    <scrollbox ref={scroll} height={Math.min(12, Math.max(2, props.view.lines.length))} scrollbarOptions={{ visible: false }}>
      <For each={props.view.lines}>{(line, index) => {
        let text!: TextRenderable;
        return <text ref={text} id={`structural-line-${index()}`} onMouseDown={event => {
          let column = event.x - text.x;
          for (const chunk of line) {
            column -= Bun.stringWidth(chunk.text);
            if (column < 0) { if (chunk.path) props.focus(chunk.path); break; }
          }
        }}><For each={line}>{chunk => <span style={{ fg: chunk.selected ? colors.bg : tokenColors[chunk.token ?? ""] ?? colors.text, bg: chunk.selected ? colors.accent : undefined, underline: chunk.error }}>{chunk.text}</span>}</For></text>;
      }}</For>
    </scrollbox>
    <text fg={colors.muted}>{props.view.type || "n integer · s string · @ package · F1 all shortcuts"}</text>
    <For each={props.view.errors.slice(0, 2)}>{error => <text fg={colors.red}>{error}</text>}</For>
  </box>;
}
