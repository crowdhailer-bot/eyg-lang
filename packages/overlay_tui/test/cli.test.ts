import { expect, test } from "bun:test";
import { fileURLToPath } from "node:url";

const main = fileURLToPath(new URL("../src/main.ts", import.meta.url));
const original = new URL("../build/dev/javascript/eyg_cli/eyg_cli.mjs", import.meta.url).href;
const gleam = new URL("../build/dev/javascript/eyg_cli/gleam.mjs", import.meta.url).href;
const system = new URL("../build/dev/javascript/loam/loam/system.mjs", import.meta.url).href;
const cases = [
  ["help"], ["version"], ["overlay", "--help"], ["signatory", "invalid"],
  ["eval", "-c", "!int_add(20, 22)"],
  ["run", "-c", 'perform StandardOut("hello")'],
  ["script", "-c", '{script: (args) -> { let _ = perform StandardOut(!head(args)) 0 }}', "hello"],
  ["check", "-c", "(x) -> { x }"],
  ["parse", "-c", "{answer: 42}"],
  ["compile", "-c", "!int_add(20, 22)"],
  ["eval", "-c", "missing"],
  ["eval", "-"],
  [],
];

async function run(command: string[], input: string) {
  const process = Bun.spawn(command, { cwd: fileURLToPath(new URL("../../..", import.meta.url)), stdin: new Blob([input]), stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([new Response(process.stdout).text(), new Response(process.stderr).text(), process.exited]);
  return { stdout, stderr, code };
}

test.each(cases)("noninteractive command retains CLI streams and status: %j", async (...args: string[]) => {
  const input = args.length ? "!int_add(20, 22)" : "let answer = 42\nanswer\n\n";
  const expected = await run([process.execPath, "-e", `import { start } from ${JSON.stringify(original)}; import { toList } from ${JSON.stringify(gleam)}; import { run } from ${JSON.stringify(system)}; await run(start(toList(${JSON.stringify(args)})));`], input);
  const actual = await run([process.execPath, main, ...args], input);
  expect(actual).toEqual(expected);
});
