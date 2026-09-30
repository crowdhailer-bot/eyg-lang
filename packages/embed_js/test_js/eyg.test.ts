import { expect, test } from "bun:test";
import { createShell } from "../dist/eyg.mjs";

const effects = {
  Add: { lift: "integer", lower: "integer" },
  Find: { lift: "string", lower: { result: { ok: { record: { id: "integer", done: "boolean" } }, error: "unit" } } },
} as const;

function counter() {
  let total = 0;
  return {
    Add: (n: number) => (total += n),
    Find: (name: string) => (name === "a" ? { $: "Ok", value: { id: 1, done: true } } : { $: "Error" }),
  };
}

test("code runs with the host's effects", async () => {
  const shell = await createShell({ effects });
  expect(shell.run("let _ = perform Add(2)\nperform Add(3)", counter())).toEqual({ value: 5, display: "5" });
});

test("variables are kept between runs", async () => {
  const shell = await createShell({ effects });
  expect(shell.run("let x = 4", counter())).toEqual({});
  expect(shell.run("!int_add(x, 1)", counter()).value).toBe(5);
});

test("values cross as plain javascript", async () => {
  const shell = await createShell({ effects });
  expect(shell.run('perform Find("a")', counter()).value).toEqual({ $: "Ok", value: { id: 1, done: true } });
  expect(shell.run('match perform Find("b") { Ok(_) -> { 1 } Error(_) -> { 0 } }', counter()).value).toBe(0);
});

test("an effect the host does not offer does not run", async () => {
  const shell = await createShell({ effects });
  const run = shell.run("perform Launch({})", counter());
  expect(run.error).toStartWith("The code did not type check, nothing ran.");
});

test("a reply of the wrong type stops the program", async () => {
  const shell = await createShell({ effects });
  const run = shell.run("perform Add(1)", { Add: () => "one" });
  expect(run.error).toBe('The program stopped.\nAdd failed: the reply "one" is not a Integer');
});

test("modules are in scope by name", async () => {
  const shell = await createShell({
    effects,
    modules: { lib: '{readme: "Adds", twice: (n) -> { let _ = perform Add(n) perform Add(n) }}' },
  });
  expect(shell.text("lib")).toBe("Adds");
  expect(shell.run("lib.twice(3)", counter()).value).toBe(6);
});

test("handlers may wait", async () => {
  const shell = await createShell({ effects });
  const run = await shell.runAsync("perform Add(7)", { Add: async (n: number) => n * 2 });
  expect(run.value).toBe(14);
});
