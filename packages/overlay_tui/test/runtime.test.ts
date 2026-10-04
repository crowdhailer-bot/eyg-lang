import { expect, test } from "bun:test";
import { ReplRuntime } from "../src/runtime";
import type { RuntimeEvent } from "../src/protocol";

test("REPL retains bindings, type queries, output and completed effects", async () => {
  const events: RuntimeEvent[] = [];
  const repl = new ReplRuntime(event => events.push(event), async () => "");
  await repl.initialize([]);
  await repl.evaluate(1, "let answer = 42");
  await repl.evaluate(2, "!int_add(answer, 1)");
  await repl.evaluate(3, "/type answer");
  await repl.evaluate(4, 'perform StandardOut("hello")');
  const done = events.filter(event => event.type === "complete");
  expect(done[1]?.results).toEqual([{ text: "43", error: false }]);
  expect(done[2]?.results[0]?.text).toContain("Int");
  expect(events).toContainEqual({ type: "output", id: 4, text: "hello", error: false });
  expect(events.find(event => event.type === "effect" && event.id === 4)).toEqual({
    type: "effect", id: 4, effect: { label: "StandardOut", input: '"hello"', output: "{}" },
  });
});

test("shell config loads initial scope using Break", async () => {
  const events: RuntimeEvent[] = [];
  const repl = new ReplRuntime(event => events.push(event), async () => "");
  await repl.initialize(["shell", "-c", '{shell: (_) -> { let seed = 9 perform Break({}) }}']);
  await repl.evaluate(1, "seed");
  expect(events.find(event => event.type === "complete")?.results).toEqual([{ text: "9", error: false }]);
});

test("errors preserve existing scope and the next input still evaluates", async () => {
  const events: RuntimeEvent[] = [];
  const repl = new ReplRuntime(event => events.push(event), async () => "");
  await repl.initialize([]);
  await repl.evaluate(1, "let value = 7");
  await repl.evaluate(2, "missing_variable");
  await repl.evaluate(3, "value");
  const done = events.filter(event => event.type === "complete");
  expect(done[1]?.results[0]?.error).toBe(true);
  expect(done[2]?.results).toEqual([{ text: "7", error: false }]);
});

test("StandardIn asks the frontend without reading its terminal descriptor", async () => {
  const events: RuntimeEvent[] = [];
  const repl = new ReplRuntime(event => events.push(event), async () => "typed input");
  await repl.initialize([]);
  await repl.evaluate(1, "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }");
  expect(events.find(event => event.type === "complete")?.results[0]?.text).toContain("typed input");
  expect(events.find(event => event.type === "effect")?.effect.label).toBe("StandardIn");
});
