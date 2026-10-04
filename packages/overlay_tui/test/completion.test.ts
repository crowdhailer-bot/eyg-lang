import { expect, test } from "bun:test";
import { complete } from "../src/completion";
import { tokens } from "../src/highlight";

test("package completion uses cursor range and only matching published names", async () => {
  expect(await complete("@sta.integer.add", 4, ["json", "standard"], process.cwd())).toEqual([
    { label: "@standard", insert: "@standard", detail: "hub package", from: 0, to: 4 },
  ]);
});
test("file completion resolves import paths against the session directory", async () => {
  const source = 'import "./src/comp';
  const results = await complete(source, source.length, [], process.cwd());
  expect(results.some(item => item.label === "./src/completion.ts")).toBe(true);
  expect(await complete('import "./absent/', 17, [], process.cwd())).toEqual([]);
});
test("highlighting keeps strings and comments intact", () => {
  expect(tokens('let x = "@not_a_package" // !not_a_builtin').map(token => token.kind)).toEqual(["keyword", "string", "comment"]);
});
