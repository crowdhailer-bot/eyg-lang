import { expect, test } from "bun:test";
import { ReplRuntime } from "../src/runtime";
import type { RuntimeEvent, StructuralView } from "../src/protocol";

async function session(source = "") {
  const events: RuntimeEvent[] = [];
  const runtime = new ReplRuntime(event => events.push(event), async () => "");
  await runtime.initialize([]);
  const view = (): StructuralView => events.findLast(event => event.type === "structure")!.view;
  const key = (key: string) => runtime.structure({ action: "key", key });
  const answer = (text: string) => runtime.structure({ action: "answer", text });
  runtime.structure({ action: "enter", source });
  return { runtime, events, view, key, answer };
}

test("structural selection edits one argument, supports undo/redo, and evaluates the changed IR", async () => {
  const { runtime, events, view, key, answer } = await session("!int_add(20, 22)");
  key("right"); key("right"); key("n");
  expect(view().input?.value).toBe("20");
  answer("40"); expect(view().source).toBe("!int_add(40, 22)");
  key("z"); expect(view().source).toBe("!int_add(20, 22)");
  key("Z"); expect(view().source).toBe("!int_add(40, 22)");
  await runtime.evaluate(1, "ignored text", true);
  expect(events.find(event => event.type === "complete")?.results).toEqual([{ text: "62", error: false }]);
  key("up"); expect(view().source).toBe("!int_add(40, 22)");
  key("down"); expect(view().source).toBe("Vacant");
});

test("structural effect construction offers computer effects and logs the actual run", async () => {
  const { runtime, events, view, key, answer } = await session();
  key("p");
  expect(view().input?.hints.some(([name]) => name === "StandardOut")).toBe(true);
  answer("StandardOut"); key(" "); key("s"); answer("structural hello");
  expect(view().source).toContain('perform StandardOut("structural hello")');
  await runtime.evaluate(1, "", true);
  expect(events).toContainEqual({ type: "effect", id: 1, effect: { label: "StandardOut", input: '"structural hello"', output: "{}" } });
});

test("binary structural values survive clipboard JSON and become bindings visible from text", async () => {
  const { runtime, events, view, key, answer } = await session();
  key("b"); key("y");
  const copied = events.find(event => event.type === "clipboard");
  expect(copied?.text).toContain('"0"');
  key("d"); runtime.structure({ action: "paste", text: copied!.text });
  key("e"); answer("bytes");
  await runtime.evaluate(1, "", true);
  await runtime.evaluate(2, "/type bytes");
  expect(events.filter(event => event.type === "complete").find(event => event.id === 2)?.results[0]?.text).toContain("Binary");
  expect(view().source).toBe("Vacant");
});

test("structural definitions and text definitions share scope, type hints and type queries", async () => {
  const { runtime, events, view, key } = await session("let answer = 42");
  await runtime.evaluate(1, "", true);
  await runtime.evaluate(2, "!int_add(answer, 1)");
  await runtime.evaluate(3, "/type answer");
  key("v");
  expect(view().input?.hints).toContainEqual(["answer", "Integer"]);
  expect(events.filter(event => event.type === "complete").find(event => event.id === 2)?.results).toEqual([{ text: "43", error: false }]);
  expect(events.filter(event => event.type === "complete").find(event => event.id === 3)?.results[0]?.text).toContain("Int");
});

test("local module loading supplies field completion without losing the import", async () => {
  let resolve!: () => void;
  const loaded = new Promise<void>(done => { resolve = done; });
  let view!: StructuralView;
  const runtime = new ReplRuntime(event => {
    if (event.type === "structure") { view = event.view; if (!view.errors.length && view.type.includes("count")) resolve(); }
  }, async () => "");
  await runtime.initialize([]);
  runtime.structure({ action: "enter", source: 'import "./test/fixtures/module.eyg"' });
  await loaded;
  runtime.structure({ action: "key", key: "g" });
  expect(view.input?.hints).toContainEqual(["count", "Integer"]);
  runtime.structure({ action: "answer", text: "count" });
  expect(view.source).toContain("./test/fixtures/module.eyg");
  expect(view.type).toBe("Integer");
}, 3000);

test("folding preserves the source and malformed input preserves the selected node", async () => {
  const { runtime, view, key, answer } = await session("(x) -> { let y = x y }");
  const before = view().source;
  key("right"); key("right"); key("k");
  expect(view().source).toBe(before);
  runtime.structure({ action: "enter", source: "22" }); key("n"); answer("invalid");
  expect(view().message).toBe("Enter an integer");
  expect(view().source).toBe("22");
  runtime.structure({ action: "cancel" }); expect(view().input).toBeUndefined();
});

test("a failed structural run leaves its expression available to correct", async () => {
  const { runtime, events, view } = await session('!int_add(20, "wrong")');
  await runtime.evaluate(1, "", true);
  expect(events.find(event => event.type === "complete")?.results[0]?.error).toBe(true);
  expect(view().source).toBe('!int_add(20, "wrong")');
  runtime.structure({ action: "focus", path: [2] });
  runtime.structure({ action: "key", key: "n" });
  runtime.structure({ action: "answer", text: "22" });
  await runtime.evaluate(2, "", true);
  expect(events.filter(event => event.type === "complete").at(-1)?.results).toEqual([{ text: "42", error: false }]);
  expect(view().errors).toEqual([]);
});
