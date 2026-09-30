// Import a compiled module and run its program with a few effects.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export async function evaluate(source, input) {
  // bun reads a data: url as CommonJS, so the module goes through a file.
  const path = join(mkdtempSync(join(tmpdir(), "eyg-module-")), "program.mjs");
  writeFileSync(path, source);
  const module = (await import(path)).default;
  const handlers = {
    Double: (x) => x * 2,
    Wait: (x) => new Promise((resolve) => setTimeout(() => resolve(x), 1)),
  };
  const result = {};
  if (typeof module.program === "function") {
    result.called = module.run(module.program(input), handlers);
  } else if (module.program instanceof module.Eff && module.program.label === "Wait") {
    result.async = await module.runAsync(module.program, handlers);
  } else {
    result.sync = module.run(module.program, handlers);
  }
  return result;
}
